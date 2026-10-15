package db

// Backup archives contain only ciphertext and wrapped keys. The client adds its
// recovery material and password protection before writing a portable backup.
import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

const (
	BackupMaxBytes   = 256 << 20
	BackupMaxEntries = 50000
	backupFormat     = "whisperingtime-backup"
)

type backupError string

func (e backupError) Error() string { return string(e) }

// BackupErrorMessage permits only our fixed, non-sensitive messages to cross
// the RPC boundary. Driver errors can contain SQL values or storage endpoints.
func BackupErrorMessage(err error) string {
	var safe backupError
	if errors.As(err, &safe) {
		return string(safe)
	}
	return "备份或恢复失败，请检查服务端数据库和媒体存储后重试"
}

// BackupObjectStore makes the archive independent of singleton clients, buckets,
// and the application database. It is also used by isolated recovery checks.
type BackupObjectStore interface {
	ReadObject(context.Context, string) (io.ReadCloser, error)
	WriteObject(context.Context, string, io.Reader, int64, string) error
	DeleteObject(context.Context, string) error
}

type BackupTheme struct {
	ID           string    `json:"id"`
	Name         []byte    `json:"name"`
	EncryptedKey []byte    `json:"encrypted_key"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}
type BackupGroup struct {
	ID             string     `json:"id"`
	ThemeID        string     `json:"theme_id"`
	Name           []byte     `json:"name"`
	EncryptedKey   []byte     `json:"encrypted_key"`
	DefaultGroup   bool       `json:"default_group"`
	LevelsStr      string     `json:"levels_str"`
	ViewType       int        `json:"view_type"`
	SortType       int        `json:"sort_type"`
	AutoFreezeDays int        `json:"auto_freeze_days"`
	OverAt         *time.Time `json:"over_at"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}
type BackupDocument struct {
	ID              string    `json:"id"`
	GroupID         string    `json:"group_id"`
	Title           []byte    `json:"title"`
	Rich            []byte    `json:"rich"`
	Scales          []byte    `json:"scales"`
	Level           []byte    `json:"level"`
	EncryptedKey    []byte    `json:"encrypted_key"`
	IsShowTool      bool      `json:"is_show_tool"`
	DisplayPriority int       `json:"display_priority"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}
type BackupPermission struct {
	ResourceType string    `json:"resource_type"`
	ResourceID   string    `json:"resource_id"`
	EncryptedKey []byte    `json:"encrypted_key"`
	Role         string    `json:"role"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}
type BackupScaleTemplate struct {
	ID                string    `json:"id"`
	EncryptedMetadata []byte    `json:"encrypted_metadata"`
	CreatedAt         time.Time `json:"created_at"`
}
type BackupFile struct {
	ID                string    `json:"id"`
	DocumentID        string    `json:"document_id"`
	ObjectPath        string    `json:"object_path"`
	Mime              string    `json:"mime"`
	Size              int64     `json:"size"`
	EncryptedKey      []byte    `json:"encrypted_key"`
	IV                []byte    `json:"iv"`
	EncryptedMetadata []byte    `json:"encrypted_metadata"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
	ArchivePath       string    `json:"archive_path"`
	SHA256            string    `json:"sha256"`
}
type BackupManifest struct {
	Format         string                `json:"format"`
	Version        int                   `json:"version"`
	BackupID       string                `json:"backup_id"`
	CreatedAt      time.Time             `json:"created_at"`
	SourceUserID   string                `json:"source_user_id"`
	Themes         []BackupTheme         `json:"themes"`
	Groups         []BackupGroup         `json:"groups"`
	Documents      []BackupDocument      `json:"documents"`
	Permissions    []BackupPermission    `json:"permissions"`
	ScaleTemplates []BackupScaleTemplate `json:"scale_templates"`
	Files          []BackupFile          `json:"files"`
}
type BackupSummary struct {
	BackupID       string `json:"backup_id"`
	Themes         int    `json:"themes"`
	Groups         int    `json:"groups"`
	Documents      int    `json:"documents"`
	Files          int    `json:"files"`
	ScaleTemplates int    `json:"scale_templates"`
	MediaBytes     int64  `json:"media_bytes"`
}

func (m *BackupManifest) Summary() BackupSummary {
	s := BackupSummary{BackupID: m.BackupID, Themes: len(m.Themes), Groups: len(m.Groups), Documents: len(m.Documents), Files: len(m.Files), ScaleTemplates: len(m.ScaleTemplates)}
	for _, f := range m.Files {
		s.MediaBytes += f.Size
	}
	return s
}

// ExportBackup holds one PostgreSQL repeatable-read snapshot while reading all
// metadata. Every media object must be readable with its recorded byte length.
func ExportBackup(ctx context.Context, database *gorm.DB, uid string, store BackupObjectStore) ([]byte, error) {
	u, err := backupUUID(uid)
	if err != nil {
		return nil, err
	}
	m := BackupManifest{Format: backupFormat, Version: 1, BackupID: uuid.NewString(), CreatedAt: time.Now().UTC(), SourceUserID: uid,
		Themes: []BackupTheme{}, Groups: []BackupGroup{}, Documents: []BackupDocument{}, Permissions: []BackupPermission{}, ScaleTemplates: []BackupScaleTemplate{}, Files: []BackupFile{}}
	err = database.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var themes []ThemeModel
		var groups []GroupModel
		var docs []DocModel
		var perms []PermissionModel
		var files []FileMetaModel
		var scales []ScaleTemplateModel
		for _, target := range []interface{}{&themes, &groups, &docs, &perms, &files, &scales} {
			if err := tx.Where("uid = ?", u).Limit(BackupMaxEntries + 1).Find(target).Error; err != nil {
				return err
			}
		}
		if len(themes)+len(groups)+len(docs)+len(perms)+len(files)+len(scales) > BackupMaxEntries {
			return backupError("备份记录超过 50000 条")
		}
		for _, t := range themes {
			m.Themes = append(m.Themes, BackupTheme{t.ID.String(), t.Name, t.EncryptedKey, t.CreatedAt, t.UpdatedAt})
		}
		for _, g := range groups {
			m.Groups = append(m.Groups, BackupGroup{g.ID.String(), g.TID.String(), g.Name, g.EncryptedKey, g.DefaultGroup, g.LevelsStr, g.ViewType, g.SortType, g.AutoFreezeDays, g.OverAt, g.CreatedAt, g.UpdatedAt})
		}
		for _, d := range docs {
			m.Documents = append(m.Documents, BackupDocument{d.ID.String(), d.GID.String(), nonNil(d.Title), nonNil(d.Rich), nonNil(d.Scales), nonNil(d.Level), d.EncryptedKey, d.IsShowTool, d.DisplayPriority, d.CreatedAt, d.UpdatedAt})
		}
		// Soft-deleted resources are not restored, so their retained permission
		// rows are intentionally excluded. Unexpected live relations fail below.
		resources := map[string]bool{}
		for _, t := range m.Themes {
			resources[ResourceTypeTheme+":"+t.ID] = true
		}
		for _, g := range m.Groups {
			resources[ResourceTypeGroup+":"+g.ID] = true
		}
		for _, d := range m.Documents {
			resources[ResourceTypeDoc+":"+d.ID] = true
		}
		for _, p := range perms {
			if resources[p.ResourceType+":"+p.ResourceID.String()] {
				m.Permissions = append(m.Permissions, BackupPermission{p.ResourceType, p.ResourceID.String(), p.EncryptedKey, p.Role, p.CreatedAt, p.UpdatedAt})
			}
		}
		// The reader uses the owner's permission envelope. Older theme/group
		// rename paths can leave the denormalized resource column stale; export
		// the envelope actually used for decryption into both archive locations.
		permissionKeys := map[string][]byte{}
		for _, p := range m.Permissions {
			permissionKeys[p.ResourceType+":"+p.ResourceID] = p.EncryptedKey
		}
		for i := range m.Themes {
			m.Themes[i].EncryptedKey = permissionKeys[ResourceTypeTheme+":"+m.Themes[i].ID]
		}
		for i := range m.Groups {
			m.Groups[i].EncryptedKey = permissionKeys[ResourceTypeGroup+":"+m.Groups[i].ID]
		}
		for i := range m.Documents {
			m.Documents[i].EncryptedKey = permissionKeys[ResourceTypeDoc+":"+m.Documents[i].ID]
		}
		for _, s := range scales {
			m.ScaleTemplates = append(m.ScaleTemplates, BackupScaleTemplate{s.ID.String(), s.EncryptedMetadata, s.CreatedAt})
		}
		for _, f := range files {
			m.Files = append(m.Files, BackupFile{f.ID.String(), f.DID.String(), f.ObjectPath, f.Mime, f.Size, f.EncryptedKey, nonNil(f.IV), nonNil(f.EncryptedMetadata), f.CreatedAt, f.UpdatedAt, "media/" + f.ID.String() + ".bin", ""})
		}
		return nil
	}, &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	if err != nil {
		return nil, fmt.Errorf("读取备份快照失败: %w", err)
	}
	media := map[string][]byte{}
	var total int64
	for i := range m.Files {
		f := &m.Files[i]
		if store == nil {
			return nil, backupError("媒体存储不可用")
		}
		if f.Size < 16 || f.Size > BackupMaxBytes-total {
			return nil, backupError("备份媒体大小无效或超过 256 MiB")
		}
		r, err := store.ReadObject(ctx, f.ObjectPath)
		if err != nil {
			return nil, backupError("图片缺失或无法读取，完整备份未生成")
		}
		data, readErr := io.ReadAll(io.LimitReader(r, f.Size+1))
		closeErr := r.Close()
		if readErr != nil || closeErr != nil || int64(len(data)) != f.Size {
			return nil, backupError("图片缺失、无法读取或大小不一致，完整备份未生成")
		}
		sum := sha256.Sum256(data)
		f.SHA256 = hex.EncodeToString(sum[:])
		media[f.ArchivePath] = data
		total += f.Size
	}
	if err := validateBackup(&m, media); err != nil {
		return nil, fmt.Errorf("备份内容不完整: %w", err)
	}
	return encodeBackup(&m, media)
}

func nonNil(v []byte) []byte {
	if v == nil {
		return []byte{}
	}
	return v
}
func backupUUID(s string) (uuid.UUID, error) {
	u, e := uuid.Parse(s)
	if e != nil || u == uuid.Nil || u.String() != s {
		return uuid.Nil, backupError("备份含无效 UUID")
	}
	return u, nil
}
func validCipher(b []byte, optional bool) bool { return (optional && len(b) == 0) || len(b) >= 28 }
func validTime(t time.Time) bool               { return !t.IsZero() && t.Year() >= 1970 && t.Year() <= 9999 }

// validateBackup is shared by export and import; an archive with any missing
// parent, envelope, or object is rejected as a whole.
func validateBackup(m *BackupManifest, media map[string][]byte) error {
	if m.Format != backupFormat || m.Version != 1 {
		return backupError("不支持的备份格式或版本")
	}
	if m.Themes == nil || m.Groups == nil || m.Documents == nil || m.Permissions == nil || m.ScaleTemplates == nil || m.Files == nil {
		return backupError("备份清单缺少完整数据数组")
	}
	if _, e := backupUUID(m.BackupID); e != nil {
		return e
	}
	if _, e := backupUUID(m.SourceUserID); e != nil {
		return e
	}
	if !validTime(m.CreatedAt) {
		return backupError("备份日期无效")
	}
	if 1+len(m.Files) > BackupMaxEntries || len(m.Themes)+len(m.Groups)+len(m.Documents)+len(m.Permissions)+len(m.ScaleTemplates)+len(m.Files) > BackupMaxEntries {
		return backupError("备份记录过多")
	}
	ids := map[string]bool{}
	themes := map[string]bool{}
	groups := map[string]bool{}
	docs := map[string]bool{}
	keys := map[string][]byte{}
	add := func(id string, created, updated time.Time) error {
		if _, e := backupUUID(id); e != nil {
			return e
		}
		if ids[id] {
			return backupError("备份资源 ID 重复")
		}
		ids[id] = true
		if !validTime(created) || !validTime(updated) {
			return backupError("记录日期无效")
		}
		return nil
	}
	for _, t := range m.Themes {
		if e := add(t.ID, t.CreatedAt, t.UpdatedAt); e != nil {
			return e
		}
		if !validCipher(t.Name, false) || len(t.EncryptedKey) != 60 {
			return backupError("主题密文或密钥缺失")
		}
		themes[t.ID] = true
		keys[ResourceTypeTheme+":"+t.ID] = t.EncryptedKey
	}
	for _, g := range m.Groups {
		if e := add(g.ID, g.CreatedAt, g.UpdatedAt); e != nil {
			return e
		}
		if !themes[g.ThemeID] {
			return backupError("分组缺少所属主题")
		}
		if !validCipher(g.Name, false) || len(g.EncryptedKey) != 60 {
			return backupError("分组密文或密钥缺失")
		}
		if g.OverAt != nil && !validTime(*g.OverAt) {
			return backupError("分组结束时间无效")
		}
		groups[g.ID] = true
		keys[ResourceTypeGroup+":"+g.ID] = g.EncryptedKey
	}
	for _, d := range m.Documents {
		if e := add(d.ID, d.CreatedAt, d.UpdatedAt); e != nil {
			return e
		}
		if !groups[d.GroupID] {
			return backupError("记录缺少所属分组")
		}
		if len(d.EncryptedKey) != 60 || !validCipher(d.Title, true) || !validCipher(d.Rich, true) || !validCipher(d.Scales, true) || (!validCipher(d.Level, true) && len(d.Level) != 1) {
			return backupError("记录密文或密钥不完整")
		}
		docs[d.ID] = true
		keys[ResourceTypeDoc+":"+d.ID] = d.EncryptedKey
	}
	seenPerm := map[string]bool{}
	for _, p := range m.Permissions {
		k := p.ResourceType + ":" + p.ResourceID
		if seenPerm[k] || keys[k] == nil || !bytes.Equal(keys[k], p.EncryptedKey) || p.Role != RoleOwner || !validTime(p.CreatedAt) || !validTime(p.UpdatedAt) {
			return backupError("资源权限密钥不一致或缺失")
		}
		seenPerm[k] = true
	}
	if len(seenPerm) != len(keys) {
		return backupError("资源缺少解密权限密钥")
	}
	for _, s := range m.ScaleTemplates {
		if e := add(s.ID, s.CreatedAt, s.CreatedAt); e != nil {
			return e
		}
		var env struct {
			V int    `json:"v"`
			C []byte `json:"c"`
			K []byte `json:"k"`
		}
		if json.Unmarshal(s.EncryptedMetadata, &env) != nil || env.V != 1 || !validCipher(env.C, false) || len(env.K) != 60 {
			return backupError("刻度模板解密信息不完整")
		}
	}
	var total int64
	for _, f := range m.Files {
		if e := add(f.ID, f.CreatedAt, f.UpdatedAt); e != nil {
			return e
		}
		if !docs[f.DocumentID] {
			return backupError("图片缺少所属记录")
		}
		if f.ObjectPath == "" || f.Mime == "" || len(f.Mime) > 255 || len(f.EncryptedKey) != 60 || (len(f.IV) != 0 && len(f.IV) != 12) || !validCipher(f.EncryptedMetadata, true) {
			return backupError("图片解密信息不完整")
		}
		if f.ArchivePath != "media/"+f.ID+".bin" || f.Size < 16 || f.Size > BackupMaxBytes-total {
			return backupError("图片归档路径或大小无效")
		}
		data, ok := media[f.ArchivePath]
		if !ok || int64(len(data)) != f.Size {
			return backupError("备份缺少图片或图片大小不一致")
		}
		sum := sha256.Sum256(data)
		if f.SHA256 != hex.EncodeToString(sum[:]) {
			return backupError("图片校验失败")
		}
		total += f.Size
	}
	if len(media) != len(m.Files) {
		return backupError("备份含未声明的媒体文件")
	}
	return nil
}

func encodeBackup(m *BackupManifest, media map[string][]byte) ([]byte, error) {
	manifest, err := json.Marshal(m)
	if err != nil {
		return nil, err
	}
	total := int64(len(manifest))
	for _, b := range media {
		total += int64(len(b))
	}
	if total > BackupMaxBytes {
		return nil, backupError("备份超过 256 MiB")
	}
	var out bytes.Buffer
	w := zip.NewWriter(&out)
	entry, err := w.CreateHeader(&zip.FileHeader{Name: "backup.json", Method: zip.Store})
	if err != nil {
		return nil, err
	}
	if _, err = entry.Write(manifest); err != nil {
		return nil, err
	}
	for _, f := range m.Files {
		entry, err = w.CreateHeader(&zip.FileHeader{Name: f.ArchivePath, Method: zip.Store})
		if err != nil {
			return nil, err
		}
		if _, err = entry.Write(media[f.ArchivePath]); err != nil {
			return nil, err
		}
	}
	if err = w.Close(); err != nil {
		return nil, err
	}
	if out.Len() > BackupMaxBytes {
		return nil, backupError("备份压缩文件超过 256 MiB")
	}
	return out.Bytes(), nil
}

// DecodeBackup never extracts paths to disk. It validates bounded, regular ZIP
// entries and validates every byte checksum before any recovery writes begin.
func DecodeBackup(data []byte) (*BackupManifest, map[string][]byte, error) {
	if len(data) == 0 || len(data) > BackupMaxBytes {
		return nil, nil, backupError("备份文件为空或超过 256 MiB")
	}
	r, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return nil, nil, backupError("备份 ZIP 无效")
	}
	if len(r.File) > BackupMaxEntries {
		return nil, nil, backupError("备份文件过多")
	}
	entries := map[string][]byte{}
	var total uint64
	for _, f := range r.File {
		if f.Name != "backup.json" && (!strings.HasPrefix(f.Name, "media/") || strings.Count(f.Name, "/") != 1 || !strings.HasSuffix(f.Name, ".bin")) {
			return nil, nil, backupError("备份含非法路径")
		}
		if f.Mode()&fs.ModeType != 0 || f.Method != zip.Store {
			return nil, nil, backupError("备份只允许 Store 格式普通文件")
		}
		if _, ok := entries[f.Name]; ok {
			return nil, nil, backupError("备份文件路径重复")
		}
		if f.UncompressedSize64 > BackupMaxBytes-total {
			return nil, nil, backupError("备份解压大小超过 256 MiB")
		}
		total += f.UncompressedSize64
		stream, e := f.Open()
		if e != nil {
			return nil, nil, e
		}
		b, e := io.ReadAll(io.LimitReader(stream, int64(f.UncompressedSize64)+1))
		ce := stream.Close()
		if e != nil || ce != nil || uint64(len(b)) != f.UncompressedSize64 {
			return nil, nil, backupError("备份文件损坏")
		}
		entries[f.Name] = b
	}
	manifest, ok := entries["backup.json"]
	if !ok {
		return nil, nil, backupError("缺少 backup.json 完整清单")
	}
	delete(entries, "backup.json")
	var m BackupManifest
	dec := json.NewDecoder(bytes.NewReader(manifest))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&m); err != nil {
		return nil, nil, backupError("备份清单无效")
	}
	var extra interface{}
	if dec.Decode(&extra) != io.EOF {
		return nil, nil, backupError("备份清单包含多余数据")
	}
	if err := validateBackup(&m, entries); err != nil {
		return nil, nil, err
	}
	return &m, entries, nil
}

// ImportBackup restores into an empty account. Media is written to unique staging
// paths; metadata commits in one transaction. Every failed write is compensated.
func cleanupBackupObjects(database *gorm.DB, uid string, store BackupObjectStore, uploaded []string, cause error) error {
	if len(uploaded) == 0 {
		return cause
	}
	cleanupCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	// A lost COMMIT response does not establish rollback. Prove that no rows
	// reference these unique attempt paths before deleting any object. If the
	// database cannot answer, prefer an orphan object to a broken real record.
	var references int64
	if err := database.WithContext(cleanupCtx).Unscoped().Model(&FileMetaModel{}).Where("object_path IN ?", uploaded).Count(&references).Error; err != nil || references != 0 {
		return backupError("恢复结果不确定，请重新打开核对；临时媒体暂保留")
	}
	var failures int
	for _, p := range uploaded {
		if store.DeleteObject(cleanupCtx, p) != nil {
			failures++
		}
	}
	if failures > 0 {
		return backupError("恢复未完成；临时媒体清理失败，请联系服务端维护者")
	}
	return cause
}

func ImportBackup(ctx context.Context, database *gorm.DB, uid string, store BackupObjectStore, data []byte) (BackupSummary, error) {
	u, err := backupUUID(uid)
	if err != nil {
		return BackupSummary{}, err
	}
	m, media, err := DecodeBackup(data)
	if err != nil {
		return BackupSummary{}, err
	}
	var uploaded []string

	// A random attempt suffix prevents a failed/retried request from deleting the
	// objects belonging to a previously committed restore of the same backup.
	prefix := "restore/" + uid + "/" + m.BackupID + "/" + uuid.NewString() + "/"
	err = database.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// These short-lived locks prevent concurrent creates from turning an
		// empty-account recovery into an implicit merge. No user rows are replaced.
		if e := tx.Exec(`LOCK TABLE theme, groups, doc, permission, filemeta, scale_template IN SHARE ROW EXCLUSIVE MODE`).Error; e != nil {
			return e
		}
		var users int64
		if e := tx.Model(&UserModel{}).Where("id = ?", u).Count(&users).Error; e != nil {
			return e
		}
		if users != 1 {
			return backupError("恢复目标用户不存在")
		}
		for _, model := range []interface{}{&ThemeModel{}, &GroupModel{}, &DocModel{}, &PermissionModel{}, &FileMetaModel{}, &ScaleTemplateModel{}} {
			var count int64
			if e := tx.Unscoped().Model(model).Where("uid = ?", u).Count(&count).Error; e != nil {
				return e
			}
			if count != 0 {
				return backupError("恢复只支持空账户，当前账户已有数据")
			}
		}
		// Reject ID collisions before writing objects, even in another account.
		checks := []struct {
			model interface{}
			ids   []string
		}{{&ThemeModel{}, nil}, {&GroupModel{}, nil}, {&DocModel{}, nil}, {&FileMetaModel{}, nil}, {&ScaleTemplateModel{}, nil}}
		for _, v := range m.Themes {
			checks[0].ids = append(checks[0].ids, v.ID)
		}
		for _, v := range m.Groups {
			checks[1].ids = append(checks[1].ids, v.ID)
		}
		for _, v := range m.Documents {
			checks[2].ids = append(checks[2].ids, v.ID)
		}
		for _, v := range m.Files {
			checks[3].ids = append(checks[3].ids, v.ID)
		}
		for _, v := range m.ScaleTemplates {
			checks[4].ids = append(checks[4].ids, v.ID)
		}
		for _, check := range checks {
			if len(check.ids) > 0 {
				var count int64
				if e := tx.Unscoped().Model(check.model).Where("id IN ?", check.ids).Count(&count).Error; e != nil {
					return e
				}
				if count > 0 {
					return backupError("备份 ID 与目标环境已有记录冲突，请使用独立环境")
				}
			}
		}
		for _, f := range m.Files {
			if store == nil {
				return backupError("媒体存储不可用")
			}
			p := prefix + f.ID
			uploaded = append(uploaded, p)
			if e := store.WriteObject(ctx, p, bytes.NewReader(media[f.ArchivePath]), f.Size, "application/octet-stream"); e != nil {
				return backupError("恢复图片失败，已停止恢复")
			}
		}
		// Explicit maps preserve false/zero values and all original timestamps.
		for _, t := range m.Themes {
			if e := tx.Table("theme").Create(map[string]interface{}{"id": t.ID, "uid": u, "name": t.Name, "encrypted_key": t.EncryptedKey, "created_at": t.CreatedAt, "updated_at": t.UpdatedAt}).Error; e != nil {
				return e
			}
		}
		for _, g := range m.Groups {
			if e := tx.Table("groups").Create(map[string]interface{}{"id": g.ID, "uid": u, "tid": g.ThemeID, "name": g.Name, "encrypted_key": g.EncryptedKey, "default_group": g.DefaultGroup, "levels_str": g.LevelsStr, "view_type": g.ViewType, "sort_type": g.SortType, "auto_freeze_days": g.AutoFreezeDays, "over_at": g.OverAt, "create_at": g.CreatedAt, "update_at": g.UpdatedAt}).Error; e != nil {
				return e
			}
		}
		for _, d := range m.Documents {
			if e := tx.Table("doc").Create(map[string]interface{}{"id": d.ID, "uid": u, "gid": d.GroupID, "title": d.Title, "rich": d.Rich, "scales": d.Scales, "level": d.Level, "encrypted_key": d.EncryptedKey, "is_show_tool": d.IsShowTool, "display_priority": d.DisplayPriority, "create_at": d.CreatedAt, "update_at": d.UpdatedAt}).Error; e != nil {
				return e
			}
		}
		for _, p := range m.Permissions {
			if e := tx.Table("permission").Create(map[string]interface{}{"uid": u, "resource_id": p.ResourceID, "resource_type": p.ResourceType, "role": RoleOwner, "encrypted_key": p.EncryptedKey, "created_at": p.CreatedAt, "updated_at": p.UpdatedAt}).Error; e != nil {
				return e
			}
		}
		for _, s := range m.ScaleTemplates {
			if e := tx.Table("scale_template").Create(map[string]interface{}{"id": s.ID, "uid": u, "encrypted_metadata": s.EncryptedMetadata, "created_at": s.CreatedAt}).Error; e != nil {
				return e
			}
		}
		for _, f := range m.Files {
			if e := tx.Table("filemeta").Create(map[string]interface{}{"id": f.ID, "uid": u, "did": f.DocumentID, "object_path": prefix + f.ID, "mime": f.Mime, "size": f.Size, "encrypted_key": f.EncryptedKey, "iv": f.IV, "encrypted_metadata": f.EncryptedMetadata, "created_at": f.CreatedAt, "updated_at": f.UpdatedAt}).Error; e != nil {
				return e
			}
		}
		return nil
	})
	if err != nil {
		return BackupSummary{}, cleanupBackupObjects(database, uid, store, uploaded, err)
	}
	return m.Summary(), nil
}
