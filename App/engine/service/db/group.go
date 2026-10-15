package db

import (
	"context"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	ml "github.com/acer-red/whisperingtime/engine/model"
	minioSvc "github.com/acer-red/whisperingtime/engine/service/minio"
)

// GroupModel is the gorm model for groups.
type GroupModel struct {
	ID             uuid.UUID      `gorm:"type:uuid;primaryKey;default:uuidv7()"`
	UID            uuid.UUID      `gorm:"column:uid;type:uuid;not null;index"`
	TID            uuid.UUID      `gorm:"column:tid;type:uuid;not null;index"`
	Name           []byte         `gorm:"column:name;type:bytea;not null"`
	EncryptedKey   []byte         `gorm:"column:encrypted_key;type:bytea;not null"`
	DefaultGroup   bool           `gorm:"column:default_group;not null;default:false"`
	LevelsStr      string         `gorm:"column:levels_str;type:text"`
	ViewType       int            `gorm:"column:view_type;not null;default:0"`
	SortType       int            `gorm:"column:sort_type;not null;default:0"`
	AutoFreezeDays int            `gorm:"column:auto_freeze_days;not null;default:30"`
	OverAt         *time.Time     `gorm:"column:over_at"`
	CreatedAt      time.Time      `gorm:"column:create_at;autoCreateTime"`
	UpdatedAt      time.Time      `gorm:"column:update_at;autoUpdateTime"`
	DeletedAt      gorm.DeletedAt `gorm:"column:deleted_at;index"`
	Docs           []DocModel     `gorm:"foreignKey:GID;references:ID"`
}

func (GroupModel) TableName() string { return "groups" }

type RequestGroupPost struct {
	Data struct {
		Name         []byte `json:"name"`
		CreateAt     string `json:"createAt"`
		UpdateAt     string `json:"updateAt"`
		EncryptedKey []byte `json:"encrypted_key"`
		Config       *struct {
			AutoFreezeDays *int `json:"auto_freeze_days"`
		} `json:"config"`
	} `json:"data"`
}
type RequestGroupPut struct {
	Data struct {
		Name     *[]byte `json:"name"`
		UpdateAt *string `json:"updateAt"`
		OverAt   *string `json:"overAt"`
		Config   *struct {
			Levels         *[]bool `json:"levels"`
			View_type      *int    `json:"view_type"`
			Sort_type      *int    `json:"sort_type"`
			AutoFreezeDays *int    `json:"auto_freeze_days"`
		} `json:"config"`
	} `json:"data"`
}

func parseLevels(s string) []bool {
	if s == "" {
		return []bool{true, true, true, true, true} // Default
	}
	parts := strings.Split(s, ",")
	var res []bool
	for _, p := range parts {
		b, _ := strconv.ParseBool(p)
		res = append(res, b)
	}
	// Pad if needed
	for len(res) < 5 {
		res = append(res, false)
	}
	return res
}

func serializeLevels(levels []bool) string {
	var parts []string
	for _, b := range levels {
		parts = append(parts, strconv.FormatBool(b))
	}
	return strings.Join(parts, ",")
}

func DefaultGroupConfig(levelsStr string, viewType, sortType, autoFreezeDays int) ml.GroupConfig {
	return ml.GroupConfig{
		Levels:         parseLevels(levelsStr),
		View_type:      viewType,
		Sort_type:      sortType,
		AutoFreezeDays: autoFreezeDays,
	}
}

func GroupsGet(themeID string) ([]ml.Group, error) {
	var groups []GroupModel
	tidUUID, err := uuid.Parse(themeID)
	if err != nil {
		return nil, err
	}
	if err := DB.Where("tid = ?", tidUUID).Find(&groups).Error; err != nil {
		return nil, err
	}

	var results []ml.Group
	for _, g := range groups {
		var overAt string
		if g.OverAt != nil {
			overAt = g.OverAt.Format("2006-01-02 15:04:05")
		}
		results = append(results, ml.Group{
			ID:       g.ID.String(),
			Name:     g.Name,
			CreateAt: g.CreatedAt.Format("2006-01-02 15:04:05"),
			UpdateAt: g.UpdatedAt.Format("2006-01-02 15:04:05"),
			OverAt:   overAt,
			Config:   DefaultGroupConfig(g.LevelsStr, g.ViewType, g.SortType, g.AutoFreezeDays),
		})
	}
	return results, nil
}

func GroupGet(themeID string, groupID string) (ml.Group, error) {
	var g GroupModel
	tidUUID, err := uuid.Parse(themeID)
	if err != nil {
		return ml.Group{}, err
	}
	gidUUID, err := uuid.Parse(groupID)
	if err != nil {
		return ml.Group{}, err
	}
	if err := DB.Where("id = ? AND tid = ?", gidUUID, tidUUID).First(&g).Error; err != nil {
		return ml.Group{}, err
	}

	var overAt string
	if g.OverAt != nil {
		overAt = g.OverAt.Format("2006-01-02 15:04:05")
	}

	return ml.Group{
		ID:       g.ID.String(),
		Name:     g.Name,
		CreateAt: g.CreatedAt.Format("2006-01-02 15:04:05"),
		UpdateAt: g.UpdatedAt.Format("2006-01-02 15:04:05"),
		OverAt:   overAt,
		Config:   DefaultGroupConfig(g.LevelsStr, g.ViewType, g.SortType, g.AutoFreezeDays),
	}, nil
}

func GroupsGetAndDocDetail(themeID string, _ bool) ([]ml.GroupAndDocs, error) {
	var groups []GroupModel
	if err := DB.Preload("Docs").Where("tid = ?", themeID).Find(&groups).Error; err != nil {
		return nil, err
	}

	var res []ml.GroupAndDocs
	for _, g := range groups {
		var docs []ml.Doc
		for _, d := range g.Docs {
			docs = append(docs, ml.Doc{
				ID: d.ID.String(),
				Content: ml.DocContent{
					Title:  d.Title,
					Rich:   d.Rich,
					Scales: d.Scales,
					Level:  d.Level,
				},
				CreateAt: d.CreatedAt,
				UpdateAt: d.UpdatedAt,
			})
		}

		var overAt string
		if g.OverAt != nil {
			overAt = g.OverAt.Format("2006-01-02 15:04:05")
		}

		res = append(res, ml.GroupAndDocs{
			GID:      g.ID.String(),
			Name:     g.Name,
			Docs:     docs,
			CreateAt: g.CreatedAt.Format("2006-01-02 15:04:05"),
			UpdateAt: g.UpdatedAt.Format("2006-01-02 15:04:05"),
			OverAt:   overAt,
			Config:   DefaultGroupConfig(g.LevelsStr, g.ViewType, g.SortType, g.AutoFreezeDays),
		})
	}

	return res, nil
}

func GroupGetAndDocDetail(themeID, groupID string) (ml.GroupAndDocs, error) {
	var g GroupModel
	if err := DB.Preload("Docs").Where("id = ? AND tid = ?", groupID, themeID).First(&g).Error; err != nil {
		return ml.GroupAndDocs{}, err
	}

	var docs []ml.Doc
	for _, d := range g.Docs {
		docs = append(docs, ml.Doc{
			ID: d.ID.String(),
			Content: ml.DocContent{
				Title:  d.Title,
				Rich:   d.Rich,
				Scales: d.Scales,
				Level:  d.Level,
			},
			CreateAt: d.CreatedAt,
			UpdateAt: d.UpdatedAt,
		})
	}

	var overAt string
	if g.OverAt != nil {
		overAt = g.OverAt.Format("2006-01-02 15:04:05")
	}

	return ml.GroupAndDocs{
		GID:      g.ID.String(),
		Name:     g.Name,
		Docs:     docs,
		CreateAt: g.CreatedAt.Format("2006-01-02 15:04:05"),
		UpdateAt: g.UpdatedAt.Format("2006-01-02 15:04:05"),
		OverAt:   overAt,
		Config:   DefaultGroupConfig(g.LevelsStr, g.ViewType, g.SortType, g.AutoFreezeDays),
	}, nil
}

// GroupCreateDefault creates a default group for a theme.
func GroupCreateDefault(uid, themeID string, dg RequestThemePostDefaultGroup) (string, error) {
	var gid uuid.UUID
	uidUUID, err := uuid.Parse(uid)
	if err != nil {
		return "", err
	}
	tidUUID, err := uuid.Parse(themeID)
	if err != nil {
		return "", err
	}
	parsedTime, _ := time.Parse("2006-01-02 15:04:05", dg.CreateAt)
	if parsedTime.IsZero() {
		parsedTime = time.Now()
	}

	autoFreeze := 30
	if dg.Config != nil && dg.Config.AutoFreezeDays != nil {
		autoFreeze = *dg.Config.AutoFreezeDays
	}

	newGroup := GroupModel{
		UID:            uidUUID,
		TID:            tidUUID,
		Name:           dg.Name,
		EncryptedKey:   dg.EncryptedKey,
		DefaultGroup:   true,
		LevelsStr:      "true,true,true,true,true",
		ViewType:       0,
		SortType:       0,
		AutoFreezeDays: autoFreeze,
		CreatedAt:      parsedTime,
		UpdatedAt:      parsedTime,
	}

	if err := DB.Create(&newGroup).Error; err != nil {
		return "", err
	}
	gid = newGroup.ID
	return gid.String(), nil
}

func GroupPost(uid, themeID string, req RequestGroupPost) (string, error) {
	var gid uuid.UUID
	uidUUID, err := uuid.Parse(uid)
	if err != nil {
		return "", err
	}
	tidUUID, err := uuid.Parse(themeID)
	if err != nil {
		return "", err
	}
	parsedTime, _ := time.Parse("2006-01-02 15:04:05", req.Data.CreateAt)
	if parsedTime.IsZero() {
		parsedTime = time.Now()
	}

	autoFreeze := 30
	levels := "true,true,true,true,true"
	viewType, sortType := 0, 0
	if req.Data.Config != nil {
		if req.Data.Config.AutoFreezeDays != nil {
			autoFreeze = *req.Data.Config.AutoFreezeDays
		}
	}

	newGroup := GroupModel{
		UID:            uidUUID,
		TID:            tidUUID,
		Name:           req.Data.Name,
		EncryptedKey:   req.Data.EncryptedKey,
		LevelsStr:      levels,
		ViewType:       viewType,
		SortType:       sortType,
		AutoFreezeDays: autoFreeze,
		CreatedAt:      parsedTime,
		UpdatedAt:      parsedTime,
	}

	if err := DB.Create(&newGroup).Error; err != nil {
		return "", err
	}
	gid = newGroup.ID
	return gid.String(), nil
}

func GroupPut(groupID string, req RequestGroupPut) error {
	gidUUID, err := uuid.Parse(groupID)
	if err != nil {
		return err
	}
	updates := make(map[string]interface{})

	if req.Data.Name != nil {
		updates["name"] = *req.Data.Name
	}
	if req.Data.UpdateAt != nil {
		if t, err := time.Parse("2006-01-02 15:04:05", *req.Data.UpdateAt); err == nil {
			updates["update_at"] = t
		}
	}
	if req.Data.OverAt != nil {
		if t, err := time.Parse("2006-01-02 15:04:05", *req.Data.OverAt); err == nil {
			updates["over_at"] = t
		}
	}

	if req.Data.Config != nil {
		c := req.Data.Config
		if c.Levels != nil {
			updates["levels_str"] = serializeLevels(*c.Levels)
		}
		if c.View_type != nil {
			updates["view_type"] = *c.View_type
		}
		if c.Sort_type != nil {
			updates["sort_type"] = *c.Sort_type
		}
		if c.AutoFreezeDays != nil {
			updates["auto_freeze_days"] = *c.AutoFreezeDays
		}
	}

	return DB.Model(&GroupModel{}).Where("id = ?", gidUUID).Updates(updates).Error
}

func GroupDeleteOne(groupID string) error {
	gidUUID, err := uuid.Parse(groupID)
	if err != nil {
		return err
	}
	return DB.Where("id = ?", gidUUID).Delete(&GroupModel{}).Error
}

// RefreshGroupUpdateAt bumps updateAt and optionally clears buffer state.
func RefreshGroupUpdateAt(groupID string, clearBuffer bool) error {
	return refreshGroupUpdateAt(DB, groupID, clearBuffer)
}

func refreshGroupUpdateAt(tx *gorm.DB, groupID string, clearBuffer bool) error {
	gidUUID, err := uuid.Parse(groupID)
	if err != nil {
		return err
	}
	updates := map[string]interface{}{
		"update_at": time.Now(),
	}
	if clearBuffer {
		var g GroupModel
		if err := tx.Select("over_at").Where("id = ?", gidUUID).First(&g).Error; err != nil {
			return err
		}
		if g.OverAt != nil && g.OverAt.After(time.Now()) {
			updates["over_at"] = nil
		}
	}
	result := tx.Model(&GroupModel{}).Where("id = ?", gidUUID).Updates(updates)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

// ExportAllThemesConfig exports all themes/groups/docs for a user to a zip.
func ExportAllThemesConfig(uid string) (string, error) {
	bgjID, taskID, err := createBGJob(uid, JobTypeExportAllConfig, JobPriority0, "导出完整备份")
	if err != nil {
		return "", err
	}

	go continueExportAllThemesConfig(bgjID, uid)

	return taskID, nil
}

// A completed export job always denotes one validated, complete archive.
func continueExportAllThemesConfig(jobID string, uid string) {
	if err := SetJobRunning(jobID); err != nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	data, err := ExportBackup(ctx, DB, uid, minioSvc.GetClient())
	if err != nil {
		SetJobError(jobID, JobError{Code: 1, Message: BackupErrorMessage(err)})
		return
	}
	output, err := os.CreateTemp(os.TempDir(), "WhisperingTime-Backup-*.zip")
	if err != nil {
		SetJobError(jobID, JobError{Code: 1, Message: BackupErrorMessage(err)})
		return
	}
	filename := output.Name()
	if _, err = output.Write(data); err != nil {
		output.Close()
		os.Remove(filename)
		SetJobError(jobID, JobError{Code: 1, Message: BackupErrorMessage(err)})
		return
	}
	if err = output.Close(); err != nil {
		os.Remove(filename)
		SetJobError(jobID, JobError{Code: 1, Message: BackupErrorMessage(err)})
		return
	}
	if err = SetJobCompleted(jobID, map[string]string{"filename": filename}); err != nil {
		os.Remove(filename)
	}
}
