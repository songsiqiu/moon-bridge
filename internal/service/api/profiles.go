package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"moonbridge/internal/service/store"
)

// ---- Profiles ----

// GET /profiles
func (r *Router) handleListProfiles(w http.ResponseWriter, req *http.Request) {
	if r.store == nil {
		respondError(w, http.StatusServiceUnavailable, "store_unavailable", "持久化存储不可用")
		return
	}

	profiles, err := r.store.ListProfiles()
	if err != nil {
		respondError(w, http.StatusInternalServerError, "list_profiles_failed", fmt.Sprintf("获取配置方案列表失败: %v", err))
		return
	}
	if profiles == nil {
		profiles = []store.ProfileMeta{}
	}

	respondJSON(w, http.StatusOK, profiles)
}

// GET /profiles/{name}
func (r *Router) handleGetProfile(w http.ResponseWriter, req *http.Request) {
	name := req.PathValue("name")
	if name == "" {
		respondError(w, http.StatusBadRequest, "invalid_name", "配置方案名称不能为空")
		return
	}

	if r.store == nil {
		respondError(w, http.StatusServiceUnavailable, "store_unavailable", "持久化存储不可用")
		return
	}

	profiles, err := r.store.ListProfiles()
	if err != nil {
		respondError(w, http.StatusInternalServerError, "list_profiles_failed", fmt.Sprintf("获取配置方案列表失败: %v", err))
		return
	}

	for _, p := range profiles {
		if p.Name == name {
			respondJSON(w, http.StatusOK, p)
			return
		}
	}
	respondError(w, http.StatusNotFound, "not_found", fmt.Sprintf("配置方案 %q 不存在", name))
}

// POST /profiles/{name}
func (r *Router) handleSaveProfile(w http.ResponseWriter, req *http.Request) {
	name := req.PathValue("name")
	if name == "" {
		respondError(w, http.StatusBadRequest, "invalid_name", "配置方案名称不能为空")
		return
	}

	if r.store == nil {
		respondError(w, http.StatusServiceUnavailable, "store_unavailable", "持久化存储不可用")
		return
	}

	var body struct {
		Description string `json:"description"`
	}
	if req.Body != nil {
		if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
			respondError(w, http.StatusBadRequest, "invalid_body", "请求体格式错误")
			return
		}
	}

	cfg := r.runtime.Current()
	if err := r.store.SaveProfile(name, strings.TrimSpace(body.Description), &cfg.Config); err != nil {
		respondError(w, http.StatusInternalServerError, "save_profile_failed", fmt.Sprintf("保存配置方案失败: %v", err))
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"name":    name,
		"message": fmt.Sprintf("配置方案 %q 已保存", name),
	})
}

// POST /profiles/{name}/activate
func (r *Router) handleActivateProfile(w http.ResponseWriter, req *http.Request) {
	name := req.PathValue("name")
	if name == "" {
		respondError(w, http.StatusBadRequest, "invalid_name", "配置方案名称不能为空")
		return
	}

	if r.store == nil {
		respondError(w, http.StatusServiceUnavailable, "store_unavailable", "持久化存储不可用")
		return
	}

	// Load profile config into active tables and mark active.
	if err := r.store.LoadProfile(name); err != nil {
		respondError(w, http.StatusInternalServerError, "activate_failed", fmt.Sprintf("加载配置方案失败: %v", err))
		return
	}

	// Reload the runtime config from the now-updated DB.
	newCfg, err := r.store.LoadAll()
	if err != nil {
		respondError(w, http.StatusInternalServerError, "reload_failed", fmt.Sprintf("重新加载配置失败: %v", err))
		return
	}

	if err := r.runtime.Reload(*newCfg); err != nil {
		respondError(w, http.StatusInternalServerError, "runtime_reload_failed", fmt.Sprintf("应用配置到运行时失败: %v", err))
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"name":    name,
		"message": fmt.Sprintf("已切换到配置方案 %q，服务正在使用新配置", name),
	})
}

// DELETE /profiles/{name}
func (r *Router) handleDeleteProfile(w http.ResponseWriter, req *http.Request) {
	name := req.PathValue("name")
	if name == "" {
		respondError(w, http.StatusBadRequest, "invalid_name", "配置方案名称不能为空")
		return
	}

	if r.store == nil {
		respondError(w, http.StatusServiceUnavailable, "store_unavailable", "持久化存储不可用")
		return
	}

	if err := r.store.DeleteProfile(name); err != nil {
		respondError(w, http.StatusInternalServerError, "delete_failed", fmt.Sprintf("删除配置方案失败: %v", err))
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"name":    name,
		"message": fmt.Sprintf("配置方案 %q 已删除", name),
	})
}

// PATCH /profiles/{name}/rename
func (r *Router) handleRenameProfile(w http.ResponseWriter, req *http.Request) {
	oldName := req.PathValue("name")
	if oldName == "" {
		respondError(w, http.StatusBadRequest, "invalid_name", "配置方案名称不能为空")
		return
	}

	if r.store == nil {
		respondError(w, http.StatusServiceUnavailable, "store_unavailable", "持久化存储不可用")
		return
	}

	var body struct {
		NewName string `json:"new_name"`
	}
	if req.Body != nil {
		if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
			respondError(w, http.StatusBadRequest, "invalid_body", "请求体格式错误")
			return
		}
	}
	newName := strings.TrimSpace(body.NewName)
	if newName == "" {
		respondError(w, http.StatusBadRequest, "invalid_new_name", "新名称不能为空")
		return
	}

	if err := r.store.RenameProfile(oldName, newName); err != nil {
		respondError(w, http.StatusInternalServerError, "rename_failed", fmt.Sprintf("重命名失败: %v", err))
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"old_name": oldName,
		"new_name": newName,
		"message":  fmt.Sprintf("配置方案已从 %q 重命名为 %q", oldName, newName),
	})
}

// GET /profiles/active
func (r *Router) handleGetActiveProfile(w http.ResponseWriter, req *http.Request) {
	if r.store == nil {
		respondError(w, http.StatusServiceUnavailable, "store_unavailable", "持久化存储不可用")
		return
	}

	name, err := r.store.GetActiveProfile()
	if err != nil {
		respondError(w, http.StatusInternalServerError, "get_active_failed", fmt.Sprintf("获取当前活跃配置方案失败: %v", err))
		return
	}

	if name == "" {
		respondJSON(w, http.StatusOK, map[string]any{
			"active": false,
			"name":   nil,
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]any{
		"active": true,
		"name":   name,
	})
}
