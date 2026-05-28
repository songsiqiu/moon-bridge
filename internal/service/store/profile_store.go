package store

import (
	"context"
	"fmt"

	"encoding/json"

	"moonbridge/internal/config"

	"moonbridge/internal/db"
)

// --- Profile operations ---

// SaveProfile saves the current configuration as a named profile.
func (s *SQLiteConfigStore) SaveProfile(name string, description string, cfg *config.Config) error {
	if name == "" {
		return fmt.Errorf("profile name is required")
	}

	fc := cfg.ToFileConfig()
	configYAML, err := fc.MarshalYAML()
	if err != nil {
		return fmt.Errorf("marshal config to YAML: %w", err)
	}

	ts := nowStr()
	profilesTable := s.table("profiles")

	// Upsert: preserve is_active and created_at on update.
	_, err = s.db.ExecContext(context.Background(),
		"INSERT OR REPLACE INTO "+profilesTable+
			" (name, description, config, is_active, created_at, updated_at)"+
			" VALUES (?, ?, ?,"+
			" COALESCE((SELECT is_active FROM "+profilesTable+" WHERE name = ?), 0),"+
			" COALESCE((SELECT created_at FROM "+profilesTable+" WHERE name = ?), ?), ?)",
		name, description, string(configYAML), name, name, ts, ts)
	if err != nil {
		return fmt.Errorf("save profile %q: %w", name, err)
	}
	return nil
}

// LoadProfile loads a named profile into the active configuration tables.
func (s *SQLiteConfigStore) LoadProfile(name string) error {
	if name == "" {
		return fmt.Errorf("profile name is required")
	}

	profilesTable := s.table("profiles")
	row := s.db.QueryRowContext(context.Background(),
		"SELECT config FROM "+profilesTable+" WHERE name = ?", name)

	var configYAML string
	if err := row.Scan(&configYAML); err != nil {
		return fmt.Errorf("load profile %q: %w", name, err)
	}

	cfg, err := config.LoadFromYAMLWithOptions([]byte(configYAML), config.LoadOptions{
		ExtensionSpecs: s.extensionSpecs,
	})
	if err != nil {
		return fmt.Errorf("parse profile config %q: %w", name, err)
	}

	// Seed active tables and mark active in a single transaction.
	if err := s.db.WithTx(context.Background(), func(tx db.Tx) error {
		// SeedFromConfig works with the main db, but we need it transactional.
		// Use a dedicated tx-based seed that operates on the given tx.
		if err := s.seedFromConfigTx(tx, &cfg); err != nil {
			return fmt.Errorf("seed profile %q: %w", name, err)
		}
		tbl, err := tx.Table("profiles")
		if err != nil {
			return err
		}
		ts := nowStr()
		if _, err := tx.ExecContext(context.Background(),
			"UPDATE "+tbl+" SET is_active = 0"); err != nil {
			return err
		}
		if _, err := tx.ExecContext(context.Background(),
			"UPDATE "+tbl+" SET is_active = 1, updated_at = ? WHERE name = ?",
			ts, name); err != nil {
			return err
		}
		return nil
	}); err != nil {
		return fmt.Errorf("load profile %q: %w", name, err)
	}

	return nil
}

// seedFromConfigTx seeds active tables from config within a transaction.
func (s *SQLiteConfigStore) seedFromConfigTx(tx db.Tx, cfg *config.Config) error {
	fc := cfg.ToFileConfig()
	ts := nowStr()

	providersTable, err := tx.Table("providers")
	if err != nil { return err }
	offersTable, err := tx.Table("offers")
	if err != nil { return err }
	modelsTable, err := tx.Table("models")
	if err != nil { return err }
	routesTable, err := tx.Table("routes")
	if err != nil { return err }
	settingsTable, err := tx.Table("settings")
	if err != nil { return err }

	// Clear active tables.
	for _, tbl := range []string{providersTable, offersTable, modelsTable, routesTable, settingsTable} {
		if _, err := tx.ExecContext(context.Background(), "DELETE FROM "+tbl); err != nil {
			return fmt.Errorf("clear %s: %w", tbl, err)
		}
	}

	// Settings.
	settings := buildSettings(fc)
	for key, value := range settings {
		if _, err := tx.ExecContext(context.Background(),
			"INSERT OR REPLACE INTO "+settingsTable+" (key, value) VALUES (?, ?)", key, value); err != nil {
			return fmt.Errorf("insert setting %s: %w", key, err)
		}
	}

	// Models.
	for slug, m := range fc.Models {
		metaJSON, err := json.Marshal(m)
		if err != nil { return fmt.Errorf("marshal model %s: %w", slug, err) }
		if _, err := tx.ExecContext(context.Background(),
			"INSERT OR REPLACE INTO "+modelsTable+" (slug, metadata, created_at, updated_at) VALUES (?, ?, ?, ?)",
			slug, string(metaJSON), ts, ts); err != nil {
			return fmt.Errorf("insert model %s: %w", slug, err)
		}
	}

	// Providers + Offers.
	for key, p := range fc.Providers {
		wsJSON, _ := json.Marshal(p.WebSearch)
		extJSON, _ := json.Marshal(p.Extensions)
		if _, err := tx.ExecContext(context.Background(),
			"INSERT OR REPLACE INTO "+providersTable+
				" (key, base_url, api_key, version, protocol, enabled, user_agent, web_search, extensions, created_at, updated_at)"+
				" VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?)",
			key, p.BaseURL, p.APIKey, p.Version, p.Protocol, p.UserAgent,
			string(wsJSON), string(extJSON), ts, ts); err != nil {
			return fmt.Errorf("insert provider %s: %w", key, err)
		}
		for _, offer := range p.Offers {
			var overridesJSON string
			if offer.Overrides != nil {
				b, _ := json.Marshal(*offer.Overrides)
				overridesJSON = string(b)
			}
			if _, err := tx.ExecContext(context.Background(),
				"INSERT OR REPLACE INTO "+offersTable+
					" (provider_key, model_slug, upstream_name, priority, input_price, output_price, cache_write, cache_read, overrides)"+
					" VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
				key, offer.Model, offer.UpstreamName, offer.Priority,
				offer.Pricing.InputPrice, offer.Pricing.OutputPrice,
				offer.Pricing.CacheWritePrice, offer.Pricing.CacheReadPrice,
				overridesJSON); err != nil {
				return fmt.Errorf("insert offer %s/%s: %w", key, offer.Model, err)
			}
		}
	}

	// Routes.
	for alias, r := range fc.Routes {
		extJSON, _ := json.Marshal(r.Extensions)
		wsJSON, _ := json.Marshal(r.WebSearch)
		if _, err := tx.ExecContext(context.Background(),
			"INSERT OR REPLACE INTO "+routesTable+
				" (alias, model_slug, provider_key, display_name, context_window, max_output_tokens, extensions, web_search, created_at, updated_at)"+
				" VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?)",
			alias, r.Model, r.Provider, r.DisplayName, r.ContextWindow,
			string(extJSON), string(wsJSON), ts, ts); err != nil {
			return fmt.Errorf("insert route %s: %w", alias, err)
		}
	}

	return nil
}

// ListProfiles returns all saved profiles with metadata.
func (s *SQLiteConfigStore) ListProfiles() ([]ProfileMeta, error) {
	profilesTable := s.table("profiles")
	rows, err := s.db.QueryContext(context.Background(),
		"SELECT name, COALESCE(description,''), is_active, COALESCE(created_at,''), COALESCE(updated_at,'') FROM "+profilesTable+
			" ORDER BY updated_at DESC")
	if err != nil {
		return nil, fmt.Errorf("list profiles: %w", err)
	}
	defer rows.Close()

	var profiles []ProfileMeta
	for rows.Next() {
		var p ProfileMeta
		var isActive int
		if err := rows.Scan(&p.Name, &p.Description, &isActive, &p.CreatedAt, &p.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan profile: %w", err)
		}
		p.IsActive = isActive != 0
		profiles = append(profiles, p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return profiles, nil
}

// DeleteProfile removes a named profile.
func (s *SQLiteConfigStore) DeleteProfile(name string) error {
	if name == "" {
		return fmt.Errorf("profile name is required")
	}
	profilesTable := s.table("profiles")
	_, err := s.db.ExecContext(context.Background(),
		"DELETE FROM "+profilesTable+" WHERE name = ?", name)
	if err != nil {
		return fmt.Errorf("delete profile %q: %w", name, err)
	}
	return nil
}

// GetActiveProfile returns the name of the currently active profile, if any.
func (s *SQLiteConfigStore) GetActiveProfile() (string, error) {
	profilesTable := s.table("profiles")
	row := s.db.QueryRowContext(context.Background(),
		"SELECT name FROM "+profilesTable+" WHERE is_active = 1 LIMIT 1")

	var name string
	if err := row.Scan(&name); err != nil {
		// No active profile is not an error.
		return "", nil
	}
	return name, nil
}

// SetActiveProfile marks a profile as active without loading its config.
func (s *SQLiteConfigStore) SetActiveProfile(name string) error {
	if name == "" {
		return fmt.Errorf("profile name is required")
	}
	ts := nowStr()

	return s.db.WithTx(context.Background(), func(tx db.Tx) error {
		tbl, err := tx.Table("profiles")
		if err != nil {
			return err
		}
		// Clear all active flags.
		if _, err := tx.ExecContext(context.Background(),
			"UPDATE "+tbl+" SET is_active = 0"); err != nil {
			return err
		}
		// Set the target profile as active.
		if _, err := tx.ExecContext(context.Background(),
			"UPDATE "+tbl+" SET is_active = 1, updated_at = ? WHERE name = ?",
			ts, name); err != nil {
			return err
		}
		return nil
	})
}

// ClearActiveProfile clears the active profile marker.
func (s *SQLiteConfigStore) ClearActiveProfile() error {
	profilesTable := s.table("profiles")
	_, err := s.db.ExecContext(context.Background(),
		"UPDATE "+profilesTable+" SET is_active = 0")
	if err != nil {
		return fmt.Errorf("clear active profile: %w", err)
	}
	return nil
}

// RenameProfile renames a profile.
func (s *SQLiteConfigStore) RenameProfile(oldName string, newName string) error {
	if oldName == "" || newName == "" {
		return fmt.Errorf("old and new profile names are required")
	}
	profilesTable := s.table("profiles")
	ts := nowStr()
	_, err := s.db.ExecContext(context.Background(),
		"UPDATE "+profilesTable+" SET name = ?, updated_at = ? WHERE name = ?",
		newName, ts, oldName)
	if err != nil {
		return fmt.Errorf("rename profile %q -> %q: %w", oldName, newName, err)
	}
	return nil
}
