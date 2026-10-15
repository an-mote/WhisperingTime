package db

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type backupMemoryStore struct {
	objects    map[string][]byte
	writes     int
	failWrite  int
	failRead   bool
	failDelete bool
}

func (s *backupMemoryStore) ReadObject(_ context.Context, name string) (io.ReadCloser, error) {
	b, ok := s.objects[name]
	if !ok || s.failRead {
		return nil, errors.New("missing object")
	}
	return io.NopCloser(bytes.NewReader(b)), nil
}
func (s *backupMemoryStore) WriteObject(_ context.Context, name string, r io.Reader, _ int64, _ string) error {
	s.writes++
	b, e := io.ReadAll(r)
	if e != nil {
		return e
	}
	s.objects[name] = b
	if s.writes == s.failWrite {
		return errors.New("partial write")
	}
	return nil
}
func (s *backupMemoryStore) DeleteObject(_ context.Context, name string) error {
	if s.failDelete {
		return errors.New("delete unavailable")
	}
	delete(s.objects, name)
	return nil
}

func backupFixture(t *testing.T) (*BackupManifest, map[string][]byte) {
	t.Helper()
	now := time.Date(2026, 10, 15, 1, 2, 3, 123000000, time.UTC)
	id := func() string { return uuid.NewString() }
	tid, gid, did, fid := id(), id(), id(), id()
	key := bytes.Repeat([]byte{7}, 60)
	cipher := bytes.Repeat([]byte{9}, 40)
	body := bytes.Repeat([]byte{11}, 92)
	scale, _ := json.Marshal(map[string]interface{}{"v": 1, "c": cipher, "k": key})
	m := &BackupManifest{Format: backupFormat, Version: 1, BackupID: id(), CreatedAt: now, SourceUserID: id(),
		Themes:         []BackupTheme{{tid, cipher, key, now, now}},
		Groups:         []BackupGroup{{gid, tid, cipher, key, true, "true,false,true,false,true", 2, 1, 0, &now, now, now}},
		Documents:      []BackupDocument{{did, gid, cipher, body, []byte{}, cipher, key, false, 0, now, now}},
		Permissions:    []BackupPermission{{ResourceTypeTheme, tid, key, RoleOwner, now, now}, {ResourceTypeGroup, gid, key, RoleOwner, now, now}, {ResourceTypeDoc, did, key, RoleOwner, now, now}},
		ScaleTemplates: []BackupScaleTemplate{{id(), scale, now}}}
	data := bytes.Repeat([]byte{17}, 80)
	sum := sha256.Sum256(data)
	path := "media/" + fid + ".bin"
	m.Files = []BackupFile{{fid, did, "same-name/image", "application/octet-stream", int64(len(data)), key, bytes.Repeat([]byte{1}, 12), cipher, now, now, path, hex.EncodeToString(sum[:])}}
	return m, map[string][]byte{path: data}
}

func TestBackupArchiveRoundTripAndEmptyArchive(t *testing.T) {
	m, media := backupFixture(t)
	data, e := encodeBackup(m, media)
	if e != nil {
		t.Fatal(e)
	}
	got, objects, e := DecodeBackup(data)
	if e != nil {
		t.Fatal(e)
	}
	if !reflect.DeepEqual(m, got) || !reflect.DeepEqual(media, objects) {
		t.Fatal("archive lost metadata or encrypted bytes")
	}
	empty := &BackupManifest{Format: backupFormat, Version: 1, BackupID: uuid.NewString(), CreatedAt: time.Now(), SourceUserID: uuid.NewString(), Themes: []BackupTheme{}, Groups: []BackupGroup{}, Documents: []BackupDocument{}, Permissions: []BackupPermission{}, ScaleTemplates: []BackupScaleTemplate{}, Files: []BackupFile{}}
	data, e = encodeBackup(empty, map[string][]byte{})
	if e != nil {
		t.Fatal(e)
	}
	if _, _, e = DecodeBackup(data); e != nil {
		t.Fatal(e)
	}
}

func TestBackupRejectsIncompleteManifest(t *testing.T) {
	tests := []struct {
		name   string
		mutate func(*BackupManifest, map[string][]byte)
	}{
		{"missing media", func(_ *BackupManifest, o map[string][]byte) {
			for k := range o {
				delete(o, k)
			}
		}},
		{"wrong hash", func(m *BackupManifest, _ map[string][]byte) { m.Files[0].SHA256 = strings.Repeat("0", 64) }},
		{"missing key", func(m *BackupManifest, _ map[string][]byte) { m.Documents[0].EncryptedKey = nil }},
		{"mismatched key", func(m *BackupManifest, _ map[string][]byte) {
			m.Permissions[0].EncryptedKey = bytes.Repeat([]byte{1}, 60)
		}},
		{"missing permission", func(m *BackupManifest, _ map[string][]byte) { m.Permissions = m.Permissions[:2] }},
		{"invalid parent", func(m *BackupManifest, _ map[string][]byte) { m.Groups[0].ThemeID = uuid.NewString() }},
		{"duplicate id", func(m *BackupManifest, _ map[string][]byte) { m.Groups[0].ID = m.Themes[0].ID }},
		{"invalid template", func(m *BackupManifest, _ map[string][]byte) { m.ScaleTemplates[0].EncryptedMetadata = []byte("{}") }},
		{"invalid image nonce", func(m *BackupManifest, _ map[string][]byte) { m.Files[0].IV = []byte{1, 2} }},
		{"traversal media", func(m *BackupManifest, _ map[string][]byte) { m.Files[0].ArchivePath = "media/../a.bin" }},
		{"wrong version", func(m *BackupManifest, _ map[string][]byte) { m.Version = 100 }},
		{"missing collection", func(m *BackupManifest, _ map[string][]byte) { m.ScaleTemplates = nil }},
		{"extra media", func(_ *BackupManifest, o map[string][]byte) { o["media/extra.bin"] = []byte("extra") }},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			m, o := backupFixture(t)
			tc.mutate(m, o)
			if validateBackup(m, o) == nil {
				t.Fatal("accepted incomplete backup")
			}
		})
	}
}

func TestBackupRejectsUnsafeZipEntries(t *testing.T) {
	tests := []struct {
		name   string
		names  []string
		method uint16
		size   uint64
	}{
		{"traversal", []string{"../backup.json"}, zip.Store, 0},
		{"duplicate", []string{"backup.json", "backup.json"}, zip.Store, 0},
		{"deflate", []string{"backup.json"}, zip.Deflate, 0},
		{"missing manifest", []string{"media/a.bin"}, zip.Store, 0},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var buf bytes.Buffer
			z := zip.NewWriter(&buf)
			for _, name := range tc.names {
				w, e := z.CreateHeader(&zip.FileHeader{Name: name, Method: tc.method})
				if e != nil {
					t.Fatal(e)
				}
				w.Write([]byte("{}"))
			}
			z.Close()
			if _, _, e := DecodeBackup(buf.Bytes()); e == nil {
				t.Fatal("accepted unsafe archive")
			}
		})
	}
}

func backupTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	database := documentTestDB(t)
	if e := database.AutoMigrate(&UserModel{}, &ThemeModel{}, &FileMetaModel{}, &ScaleTemplateModel{}); e != nil {
		t.Fatal(e)
	}
	return database
}
func backupTarget(t *testing.T, database *gorm.DB) string {
	t.Helper()
	u := uuid.New()
	if e := database.Create(&UserModel{ID: u}).Error; e != nil {
		t.Fatal(e)
	}
	return u.String()
}
func backupCount(t *testing.T, database *gorm.DB, uid string) int64 {
	t.Helper()
	var total int64
	for _, model := range []interface{}{&ThemeModel{}, &GroupModel{}, &DocModel{}, &PermissionModel{}, &FileMetaModel{}, &ScaleTemplateModel{}} {
		var c int64
		if e := database.Model(model).Where("uid = ?", uid).Count(&c).Error; e != nil {
			t.Fatal(e)
		}
		total += c
	}
	return total
}

func TestBackupIndependentDatabaseRoundTrip(t *testing.T) {
	source := backupTestDB(t)
	dest := backupTestDB(t)
	sourceUID := backupTarget(t, source)
	destUID := backupTarget(t, dest)
	m, media := backupFixture(t)
	input, e := encodeBackup(m, media)
	if e != nil {
		t.Fatal(e)
	}
	sourceStore := &backupMemoryStore{objects: map[string][]byte{}}
	if _, e = ImportBackup(context.Background(), source, sourceUID, sourceStore, input); e != nil {
		t.Fatal(e)
	}
	archive, e := ExportBackup(context.Background(), source, sourceUID, sourceStore)
	if e != nil {
		t.Fatal(e)
	}
	destStore := &backupMemoryStore{objects: map[string][]byte{}}
	summary, e := ImportBackup(context.Background(), dest, destUID, destStore, archive)
	if e != nil {
		t.Fatal(e)
	}
	if summary.Themes != 1 || summary.Groups != 1 || summary.Documents != 1 || summary.Files != 1 || summary.ScaleTemplates != 1 || summary.MediaBytes != 80 {
		t.Fatalf("wrong summary: %+v", summary)
	}
	var doc DocModel
	if e = dest.First(&doc, "id = ?", m.Documents[0].ID).Error; e != nil {
		t.Fatal(e)
	}
	if doc.UID.String() != destUID || !bytes.Equal(doc.Rich, m.Documents[0].Rich) || doc.IsShowTool || doc.DisplayPriority != 0 || !doc.CreatedAt.Equal(m.Documents[0].CreatedAt) {
		t.Fatal("restored content/config/time/owner differs")
	}
	var group GroupModel
	if e = dest.First(&group, "id = ?", m.Groups[0].ID).Error; e != nil {
		t.Fatal(e)
	}
	if group.AutoFreezeDays != 0 || group.LevelsStr != m.Groups[0].LevelsStr {
		t.Fatal("zero/default settings changed")
	}
	var file FileMetaModel
	if e = dest.First(&file, "id = ?", m.Files[0].ID).Error; e != nil {
		t.Fatal(e)
	}
	if file.UID.String() != destUID || !strings.HasPrefix(file.ObjectPath, "restore/"+destUID+"/") || !bytes.Equal(destStore.objects[file.ObjectPath], media[m.Files[0].ArchivePath]) {
		t.Fatal("media not rebound independently")
	}
	before := backupCount(t, dest, destUID)
	if _, e = ImportBackup(context.Background(), dest, destUID, destStore, archive); e == nil {
		t.Fatal("accepted non-empty target")
	}
	if backupCount(t, dest, destUID) != before || len(destStore.objects) != 1 {
		t.Fatal("retry changed committed recovery")
	}
}

func TestBackupMissingMediaFailsExport(t *testing.T) {
	database := backupTestDB(t)
	uid := backupTarget(t, database)
	m, media := backupFixture(t)
	archive, e := encodeBackup(m, media)
	if e != nil {
		t.Fatal(e)
	}
	store := &backupMemoryStore{objects: map[string][]byte{}}
	if _, e = ImportBackup(context.Background(), database, uid, store, archive); e != nil {
		t.Fatal(e)
	}
	store.failRead = true
	if _, e = ExportBackup(context.Background(), database, uid, store); e == nil {
		t.Fatal("missing image was silently omitted")
	}
}

func TestBackupUsesReaderEnvelopeAndPreservesLegacyOptionalFields(t *testing.T) {
	database := backupTestDB(t)
	uid := backupTarget(t, database)
	m, media := backupFixture(t)
	m.Files[0].IV = []byte{}
	m.Files[0].EncryptedMetadata = []byte{}
	m.Documents[0].Level = []byte{3}
	archive, err := encodeBackup(m, media)
	if err != nil {
		t.Fatal(err)
	}
	store := &backupMemoryStore{objects: map[string][]byte{}}
	if _, err = ImportBackup(context.Background(), database, uid, store, archive); err != nil {
		t.Fatal(err)
	}
	// Theme rename historically only updated the permission envelope. The
	// backup must use the same envelope as the production read path.
	if err = database.Model(&ThemeModel{}).Where("id = ?", m.Themes[0].ID).Update("encrypted_key", bytes.Repeat([]byte{99}, 60)).Error; err != nil {
		t.Fatal(err)
	}
	archive, err = ExportBackup(context.Background(), database, uid, store)
	if err != nil {
		t.Fatal(err)
	}
	got, _, err := DecodeBackup(archive)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got.Themes[0].EncryptedKey, m.Permissions[0].EncryptedKey) || len(got.Files[0].IV) != 0 || len(got.Files[0].EncryptedMetadata) != 0 || !bytes.Equal(got.Documents[0].Level, []byte{3}) {
		t.Fatal("reader key or optional legacy bytes changed")
	}
}

func TestBackupMediaFailureRollsBackAndCleansObjects(t *testing.T) {
	database := backupTestDB(t)
	uid := backupTarget(t, database)
	m, media := backupFixture(t)
	archive, e := encodeBackup(m, media)
	if e != nil {
		t.Fatal(e)
	}
	store := &backupMemoryStore{objects: map[string][]byte{}, failWrite: 1}
	if _, e = ImportBackup(context.Background(), database, uid, store, archive); e == nil {
		t.Fatal("accepted media write failure")
	}
	if backupCount(t, database, uid) != 0 || len(store.objects) != 0 {
		t.Fatal("failed media import left metadata or objects")
	}
}

func TestBackupDatabaseFailureRollsBackAndCleansObjects(t *testing.T) {
	database := backupTestDB(t)
	uid := backupTarget(t, database)
	m, media := backupFixture(t)
	archive, e := encodeBackup(m, media)
	if e != nil {
		t.Fatal(e)
	}
	if e = database.Exec(`CREATE FUNCTION fail_backup_insert() RETURNS trigger AS $$ BEGIN RAISE EXCEPTION 'injected write failure'; END; $$ LANGUAGE plpgsql`).Error; e != nil {
		t.Fatal(e)
	}
	if e = database.Exec(`CREATE TRIGGER fail_backup BEFORE INSERT ON scale_template FOR EACH ROW EXECUTE FUNCTION fail_backup_insert()`).Error; e != nil {
		t.Fatal(e)
	}
	store := &backupMemoryStore{objects: map[string][]byte{}}
	if _, e = ImportBackup(context.Background(), database, uid, store, archive); e == nil {
		t.Fatal("accepted database failure")
	}
	if backupCount(t, database, uid) != 0 || len(store.objects) != 0 {
		t.Fatal("database failure left partially restored metadata or media")
	}
}

func TestBackupReportsCleanupFailure(t *testing.T) {
	database := backupTestDB(t)
	uid := backupTarget(t, database)
	m, media := backupFixture(t)
	archive, e := encodeBackup(m, media)
	if e != nil {
		t.Fatal(e)
	}
	store := &backupMemoryStore{objects: map[string][]byte{}, failWrite: 1, failDelete: true}
	_, e = ImportBackup(context.Background(), database, uid, store, archive)
	if e == nil || !strings.Contains(e.Error(), "清理失败") {
		t.Fatal("cleanup failure hidden")
	}
	if backupCount(t, database, uid) != 0 {
		t.Fatal("cleanup failure committed metadata")
	}
}

func TestBackupCleanupKeepsObjectsReferencedAfterCommit(t *testing.T) {
	database := backupTestDB(t)
	uid := backupTarget(t, database)
	m, media := backupFixture(t)
	archive, err := encodeBackup(m, media)
	if err != nil {
		t.Fatal(err)
	}
	store := &backupMemoryStore{objects: map[string][]byte{}}
	if _, err = ImportBackup(context.Background(), database, uid, store, archive); err != nil {
		t.Fatal(err)
	}
	var paths []string
	if err = database.Model(&FileMetaModel{}).Where("uid = ?", uid).Pluck("object_path", &paths).Error; err != nil {
		t.Fatal(err)
	}
	err = cleanupBackupObjects(database, uid, store, paths, errors.New("commit acknowledgement lost"))
	if err == nil || !strings.Contains(err.Error(), "结果不确定") || len(store.objects) != 1 {
		t.Fatal("committed media was deleted after uncertain commit")
	}
}

func TestBackupCleanupKeepsObjectsWhenDatabaseCannotConfirmRollback(t *testing.T) {
	database := backupTestDB(t)
	uid := backupTarget(t, database)
	store := &backupMemoryStore{objects: map[string][]byte{"attempt/image": []byte("ciphertext")}}
	if err := database.Callback().Query().Before("gorm:query").Register("backup_query_failure", func(tx *gorm.DB) { tx.AddError(errors.New("database unavailable")) }); err != nil {
		t.Fatal(err)
	}
	err := cleanupBackupObjects(database, uid, store, []string{"attempt/image"}, errors.New("commit outcome unknown"))
	database.Callback().Query().Remove("backup_query_failure")
	if err == nil || !strings.Contains(err.Error(), "结果不确定") || len(store.objects) != 1 {
		t.Fatal("media removed without proving rollback")
	}
}

func TestFileMetaCreateAllowsEmbeddedNonceAndAbsentOptionalMetadata(t *testing.T) {
	database := backupTestDB(t)
	uid := backupTarget(t, database)
	meta := &FileMeta{UID: uid, DocID: uuid.NewString(), ObjectPath: "unique/image", Mime: "application/octet-stream", Size: 28, EncryptedKey: bytes.Repeat([]byte{1}, 60)}
	if _, err := FileMetaCreate(context.Background(), meta); err != nil {
		t.Fatal(err)
	}
	var stored FileMetaModel
	if err := database.First(&stored, "id = ?", meta.ID).Error; err != nil {
		t.Fatal(err)
	}
	if stored.IV == nil || stored.EncryptedMetadata == nil || len(stored.IV) != 0 || len(stored.EncryptedMetadata) != 0 {
		t.Fatal("empty optional bytes were not stored as bytea")
	}
}

func TestBackupErrorMessageDoesNotExposeDriverDetails(t *testing.T) {
	if got := BackupErrorMessage(errors.New("SQL VALUES (sensitive-ciphertext)")); strings.Contains(got, "sensitive") {
		t.Fatal("SQL details leaked")
	}
	if got := BackupErrorMessage(backupError("恢复只支持空账户，当前账户已有数据")); !strings.Contains(got, "空账户") {
		t.Fatal("actionable validation error hidden")
	}
}
