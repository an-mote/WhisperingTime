package db

import (
	"bytes"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/tengfei-xy/go-log"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	m "github.com/acer-red/whisperingtime/engine/model"
	"github.com/acer-red/whisperingtime/engine/util"
)

// DocModel is the gorm model for documents.
type DocModel struct {
	ID              uuid.UUID      `gorm:"type:uuid;primaryKey;default:uuidv7()"`
	UID             uuid.UUID      `gorm:"column:uid;type:uuid;not null;index"`
	GID             uuid.UUID      `gorm:"column:gid;type:uuid;not null;index"`
	Title           []byte         `gorm:"column:title;type:bytea"`
	Rich            []byte         `gorm:"column:rich;type:bytea"`
	Scales          []byte         `gorm:"column:scales;type:bytea"`
	Level           []byte         `gorm:"column:level;type:bytea"`
	EncryptedKey    []byte         `gorm:"column:encrypted_key;type:bytea;not null"`
	IsShowTool      bool           `gorm:"column:is_show_tool;not null;default:false"`
	DisplayPriority int            `gorm:"column:display_priority;not null;default:0"`
	CreatedAt       time.Time      `gorm:"column:create_at;autoCreateTime"`
	UpdatedAt       time.Time      `gorm:"column:update_at;autoUpdateTime"`
	DeletedAt       gorm.DeletedAt `gorm:"column:deleted_at;index"`
}

func (DocModel) TableName() string { return "doc" }

type RequestDocPost struct {
	CreationID string `json:"-"`
	Data       struct {
		Content      m.DocContent `json:"content"`
		CreateAt     string       `json:"createAt"`
		Config       *m.DocConfig `json:"config"`
		EncryptedKey []byte       `json:"encrypted_key"`
	} `json:"data"`
}

type RequestDocPut struct {
	UserID       string `json:"-"`
	EncryptedKey []byte `json:"-"`
	Doc          struct {
		Content  *m.DocContent `json:"content,omitempty" bson:"content"`
		CreateAt *string       `json:"createAt,omitempty"`
		UpdateAt *string       `json:"updateAt,omitempty"`
		Config   *m.DocConfig  `json:"config,omitempty" bson:"config"`
		ID       *string       `json:"id" bson:"did"`
	} `json:"data"`
}
type DocFilter struct {
	Year  int `json:"year"`
	Month int `json:"month"`
}

func DocsGet(groupID string, f DocFilter) ([]m.Doc, error) {
	var results []m.Doc
	var docs []DocModel

	gidUUID, err := uuid.Parse(groupID)
	if err != nil {
		return nil, err
	}

	query := DB.Where("gid = ?", gidUUID)

	if f.Year != 0 && f.Month != 0 {
		startDate := time.Date(f.Year, time.Month(f.Month), 1, 0, 0, 0, 0, time.Local)
		endDate := time.Date(f.Year, time.Month(f.Month+1), 1, 0, 0, 0, 0, time.Local)
		query = query.Where("create_at >= ? AND create_at < ?", startDate, endDate)
	}

	if err := query.Find(&docs).Error; err != nil {
		log.Error(err)
		return nil, err
	}

	for _, d := range docs {
		cfg := &m.DocConfig{
			IsShowTool:      d.IsShowTool,
			DisplayPriority: d.DisplayPriority,
		}

		results = append(results, m.Doc{
			Content: m.DocContent{
				Title:  d.Title,
				Scales: d.Scales,
				Rich:   d.Rich,
				Level:  d.Level,
			},
			CreateAt: d.CreatedAt,
			UpdateAt: d.UpdatedAt,
			Config:   cfg,
			ID:       d.ID.String(),
		})
	}

	return results, nil
}
func DocPost(uid string, groupID string, req *RequestDocPost) (string, error) {
	if req == nil || len(req.Data.EncryptedKey) == 0 {
		return "", errors.New("missing document encryption key")
	}
	uidUUID, err := uuid.Parse(uid)
	if err != nil {
		return "", err
	}
	gidUUID, err := uuid.Parse(groupID)
	if err != nil {
		return "", err
	}
	var creationUUID uuid.UUID
	if req.CreationID != "" {
		creationUUID, err = uuid.Parse(req.CreationID)
		if err != nil || creationUUID == uuid.Nil {
			return "", errors.New("invalid document creation id")
		}
	}

	newDoc := DocModel{
		ID:           creationUUID,
		UID:          uidUUID,
		GID:          gidUUID,
		Title:        req.Data.Content.Title,
		Rich:         req.Data.Content.Rich,
		Scales:       req.Data.Content.Scales,
		Level:        req.Data.Content.Level,
		CreatedAt:    util.StringtoTime(req.Data.CreateAt),
		UpdatedAt:    util.StringtoTime(req.Data.CreateAt),
		EncryptedKey: req.Data.EncryptedKey,
	}

	if req.Data.Config != nil {
		newDoc.IsShowTool = req.Data.Config.IsShowTool
		newDoc.DisplayPriority = req.Data.Config.DisplayPriority
	}

	err = DB.Transaction(func(tx *gorm.DB) error {
		var group GroupModel
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ? AND uid = ?", gidUUID, uidUUID).First(&group).Error; err != nil {
			return err
		}
		if creationUUID != uuid.Nil {
			var existing DocModel
			err := tx.Unscoped().Where("id = ?", creationUUID).First(&existing).Error
			if err == nil {
				if existing.UID != uidUUID || existing.GID != gidUUID || existing.DeletedAt.Valid {
					return errors.New("document creation id unavailable")
				}
				// A response may have been lost after a committed create. The
				// original snapshot wins; newer edits must use UpdateDoc.
				newDoc.ID = existing.ID
				return nil
			}
			if !errors.Is(err, gorm.ErrRecordNotFound) {
				return err
			}
		}
		if err := tx.Create(&newDoc).Error; err != nil {
			return err
		}
		if err := permissionUpsert(tx, uid, newDoc.ID.String(), ResourceTypeDoc, RoleOwner, req.Data.EncryptedKey); err != nil {
			return err
		}
		return refreshGroupUpdateAt(tx, groupID, true)
	})
	if err != nil {
		return "", err
	}
	return newDoc.ID.String(), nil
}

func DocPut(groupID string, docID string, req *RequestDocPut) error {
	if req == nil || req.UserID == "" {
		return errors.New("missing user id")
	}
	uidUUID, err := uuid.Parse(req.UserID)
	if err != nil {
		return err
	}
	didUUID, err := uuid.Parse(docID)
	if err != nil {
		return err
	}
	gidUUID, err := uuid.Parse(groupID)
	if err != nil {
		return err
	}
	updates := make(map[string]interface{})

	if req.Doc.Content != nil {
		if req.Doc.Content.Title != nil {
			updates["title"] = req.Doc.Content.Title
		}
		if req.Doc.Content.Rich != nil {
			updates["rich"] = req.Doc.Content.Rich
		}
		if req.Doc.Content.Scales != nil {
			updates["scales"] = req.Doc.Content.Scales
		}
		if req.Doc.Content.Level != nil {
			updates["level"] = req.Doc.Content.Level
		}
	}
	if req.Doc.CreateAt != nil {
		updates["create_at"] = util.StringtoTime(*req.Doc.CreateAt)
	}

	if req.Doc.UpdateAt != nil {
		updates["update_at"] = util.StringtoTime(*req.Doc.UpdateAt)
	}

	if req.Doc.Config != nil {
		updates["is_show_tool"] = req.Doc.Config.IsShowTool
		updates["display_priority"] = req.Doc.Config.DisplayPriority
	}

	return DB.Transaction(func(tx *gorm.DB) error {
		// Lock the parent first, matching creation's lock order.
		var group GroupModel
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ? AND uid = ?", gidUUID, uidUUID).First(&group).Error; err != nil {
			return err
		}
		var doc DocModel
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ? AND gid = ? AND uid = ?", didUUID, gidUUID, uidUUID).First(&doc).Error; err != nil {
			return err
		}
		var perm PermissionModel
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("uid = ? AND resource_id = ? AND resource_type = ? AND role = ?", uidUUID, didUUID, ResourceTypeDoc, RoleOwner).First(&perm).Error; err != nil {
			return fmt.Errorf("document owner permission unavailable; cannot safely update: %w", err)
		}
		if len(perm.EncryptedKey) == 0 {
			return errors.New("missing document encryption key; cannot safely update")
		}
		key := perm.EncryptedKey
		if len(req.EncryptedKey) > 0 {
			// A partial rewrite must keep the data key used by untouched fields.
			// Envelopes are opaque to the server, so compare the original bytes.
			if !bytes.Equal(req.EncryptedKey, perm.EncryptedKey) && !replacesAllEncryptedDocFields(req.Doc.Content, doc) {
				return errors.New("document encryption key changed; reload before updating")
			}
			key = req.EncryptedKey
		}
		updates["encrypted_key"] = key
		result := tx.Model(&DocModel{}).Where("id = ? AND gid = ? AND uid = ?", didUUID, gidUUID, uidUUID).Updates(updates)
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return gorm.ErrRecordNotFound
		}
		if err := permissionUpsert(tx, req.UserID, docID, ResourceTypeDoc, RoleOwner, key); err != nil {
			return err
		}
		return refreshGroupUpdateAt(tx, groupID, true)
	})
}

func replacesAllEncryptedDocFields(content *m.DocContent, current DocModel) bool {
	return content != nil &&
		(len(current.Title) == 0 || content.Title != nil) &&
		(len(current.Rich) == 0 || content.Rich != nil) &&
		(len(current.Scales) == 0 || content.Scales != nil) &&
		(len(current.Level) == 0 || content.Level != nil)
}

func DocDelete(groupID string, docID string) error {
	didUUID, err := uuid.Parse(docID)
	if err != nil {
		return err
	}
	gidUUID, err := uuid.Parse(groupID)
	if err != nil {
		return err
	}

	var doc DocModel
	if err := DB.Where("id = ? AND gid = ?", didUUID, gidUUID).First(&doc).Error; err != nil {
		return err
	}

	if err := DB.Delete(&doc).Error; err != nil {
		return err
	}

	if err := PermissionDelete(ResourceTypeDoc, []string{doc.ID.String()}); err != nil {
		return err
	}

	return RefreshGroupUpdateAt(groupID, true)
}

// 根据 Group ID 删除所有印迹
func DocDeleteFromGroupID(groupID string) error {
	gidUUID, err := uuid.Parse(groupID)
	if err != nil {
		return err
	}
	return DB.Where("gid = ?", gidUUID).Delete(&DocModel{}).Error
}
