package db

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"errors"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/google/uuid"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	m "github.com/acer-red/whisperingtime/engine/model"
)

// Each test uses a fresh schema in an explicitly supplied PostgreSQL database;
// application configuration and existing tables are never read or migrated.
func documentTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := os.Getenv("WHISPERINGTIME_TEST_POSTGRES_DSN")
	if dsn == "" {
		t.Skip("set WHISPERINGTIME_TEST_POSTGRES_DSN to run PostgreSQL document integration tests")
	}
	testDB, err := gorm.Open(postgres.Open(dsn), &gorm.Config{Logger: logger.Default.LogMode(logger.Silent)})
	if err != nil {
		t.Fatal("cannot open integration database")
	}
	sqlDB, err := testDB.DB()
	if err != nil {
		t.Fatal(err)
	}
	sqlDB.SetMaxOpenConns(1)
	schema := "doc_test_" + uuid.New().String()[:8]
	if err := testDB.Exec(`CREATE SCHEMA "` + schema + `"`).Error; err != nil {
		t.Fatal(err)
	}
	previous := DB
	DB = testDB
	t.Cleanup(func() {
		DB = previous
		if err := testDB.Exec(`DROP SCHEMA "` + schema + `" CASCADE`).Error; err != nil {
			t.Error(err)
		}
		_ = sqlDB.Close()
	})
	if err := testDB.Exec(`SET search_path TO "` + schema + `", public`).Error; err != nil {
		t.Fatal(err)
	}
	if err := testDB.AutoMigrate(&GroupModel{}, &DocModel{}, &PermissionModel{}); err != nil {
		t.Fatal(err)
	}
	return testDB
}

func seedDocumentGroup(t *testing.T, testDB *gorm.DB) (string, string) {
	t.Helper()
	uid, gid := uuid.New(), uuid.New()
	group := GroupModel{
		ID: gid, UID: uid, TID: uuid.New(), Name: []byte("group"), EncryptedKey: []byte("group-key"),
		CreatedAt: time.Unix(1700000000, 0), UpdatedAt: time.Unix(1700000000, 0),
	}
	if err := testDB.Create(&group).Error; err != nil {
		t.Fatal(err)
	}
	return uid.String(), gid.String()
}

func createDocument(t *testing.T, uid, gid string, content m.DocContent, wrappedKey []byte) string {
	t.Helper()
	req := &RequestDocPost{}
	req.Data.Content = content
	req.Data.EncryptedKey = wrappedKey
	req.Data.CreateAt = "1700000000"
	req.Data.Config = &m.DocConfig{IsShowTool: true, DisplayPriority: 7}
	did, err := DocPost(uid, gid, req)
	if err != nil {
		t.Fatal(err)
	}
	return did
}

func testCipher(t *testing.T) cipher.AEAD {
	t.Helper()
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		t.Fatal(err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		t.Fatal(err)
	}
	return aead
}

func encryptTestField(t *testing.T, aead cipher.AEAD, value string) []byte {
	t.Helper()
	nonce := make([]byte, aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		t.Fatal(err)
	}
	return aead.Seal(nonce, nonce, []byte(value), nil)
}

func assertDecrypt(t *testing.T, aead cipher.AEAD, value []byte, want string) {
	t.Helper()
	if len(value) < aead.NonceSize() {
		t.Fatalf("encrypted field was lost: %x", value)
	}
	plain, err := aead.Open(nil, value[:aead.NonceSize()], value[aead.NonceSize():], nil)
	if err != nil || string(plain) != want {
		t.Fatalf("decrypt got %q, %v; want %q", plain, err, want)
	}
}

func readDocument(t *testing.T, testDB *gorm.DB, did string) DocModel {
	t.Helper()
	var doc DocModel
	if err := testDB.First(&doc, "id = ?", did).Error; err != nil {
		t.Fatal(err)
	}
	return doc
}

func TestDocumentPartialUpdatesPreserveEncryptedFields(t *testing.T) {
	testDB := documentTestDB(t)
	uid, gid := seedDocumentGroup(t, testDB)
	aead := testCipher(t)
	wrappedKey := []byte("same-wrapped-data-key")
	content := m.DocContent{
		Title: encryptTestField(t, aead, "中文标题"), Rich: encryptTestField(t, aead, `{"insert":"正文第一段\\n"}`),
		Scales: encryptTestField(t, aead, `[{"name":"心情","value":3}]`), Level: encryptTestField(t, aead, "2"),
	}
	did := createDocument(t, uid, gid, content, wrappedKey)

	updates := []struct {
		name    string
		content m.DocContent
	}{
		{"title", m.DocContent{Title: encryptTestField(t, aead, "修改标题")}},
		{"body", m.DocContent{Rich: encryptTestField(t, aead, `{"insert":"修改中文正文\\n"}`)}},
		{"level", m.DocContent{Level: encryptTestField(t, aead, "4")}},
	}
	for _, update := range updates {
		t.Run(update.name, func(t *testing.T) {
			req := &RequestDocPut{UserID: uid, EncryptedKey: wrappedKey}
			req.Doc.Content = &update.content
			if err := DocPut(gid, did, req); err != nil {
				t.Fatal(err)
			}
		})
	}
	created := strconv.FormatInt(time.Date(2026, 10, 15, 3, 0, 0, 0, time.UTC).Unix(), 10)
	req := &RequestDocPut{UserID: uid, EncryptedKey: wrappedKey}
	req.Doc.CreateAt = &created
	req.Doc.Config = &m.DocConfig{IsShowTool: false, DisplayPriority: 0}
	if err := DocPut(gid, did, req); err != nil {
		t.Fatal(err)
	}

	// Read through a fresh DB query and the production list path, as on reopen.
	doc := readDocument(t, testDB, did)
	if doc.IsShowTool || doc.DisplayPriority != 0 {
		t.Fatal("explicit false/zero config values were not saved")
	}
	assertDecrypt(t, aead, doc.Title, "修改标题")
	assertDecrypt(t, aead, doc.Rich, `{"insert":"修改中文正文\\n"}`)
	assertDecrypt(t, aead, doc.Scales, `[{"name":"心情","value":3}]`)
	assertDecrypt(t, aead, doc.Level, "4")
	perm, err := PermissionGet(uid, ResourceTypeDoc, did)
	if err != nil || !bytes.Equal(perm.EncryptedKey, wrappedKey) || !bytes.Equal(doc.EncryptedKey, wrappedKey) {
		t.Fatalf("document and permission keys differ: %v", err)
	}
	docs, err := DocsGet(gid, DocFilter{Year: 2026, Month: 10})
	if err != nil || len(docs) != 1 || !docs[0].CreateAt.Equal(doc.CreatedAt) {
		t.Fatalf("reopen/filter did not recover date: %v, count=%d", err, len(docs))
	}
	assertDecrypt(t, aead, docs[0].Content.Rich, `{"insert":"修改中文正文\\n"}`)
}

func failPermissionWrites(t *testing.T, testDB *gorm.DB) {
	t.Helper()
	if err := testDB.Callback().Create().Before("gorm:create").Register("test:fail_permission", func(tx *gorm.DB) {
		if tx.Statement.Table == "permission" {
			tx.AddError(errors.New("injected permission write failure"))
		}
	}); err != nil {
		t.Fatal(err)
	}
}

func TestDocumentCreateRollsBackOnPermissionFailure(t *testing.T) {
	testDB := documentTestDB(t)
	uid, gid := seedDocumentGroup(t, testDB)
	failPermissionWrites(t, testDB)
	req := &RequestDocPost{}
	req.Data.EncryptedKey = []byte("key")
	req.Data.Content.Title = []byte("title")
	req.Data.CreateAt = "1700000000"
	if did, err := DocPost(uid, gid, req); err == nil || did != "" {
		t.Fatalf("create should fail, got id=%q error=%v", did, err)
	}
	var count int64
	if err := testDB.Model(&DocModel{}).Count(&count).Error; err != nil || count != 0 {
		t.Fatalf("failed create left a document: count=%d error=%v", count, err)
	}
}

func TestDocumentCreateRejectsWrongOwnershipAndMissingKey(t *testing.T) {
	testDB := documentTestDB(t)
	uid, gid := seedDocumentGroup(t, testDB)
	req := &RequestDocPost{}
	req.Data.EncryptedKey = []byte("key")
	req.Data.CreateAt = "1700000000"
	if _, err := DocPost(uuid.NewString(), gid, req); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("wrong owner should fail, got %v", err)
	}
	if _, err := DocPost(uid, uuid.NewString(), req); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("missing group should fail, got %v", err)
	}
	req.Data.EncryptedKey = nil
	if _, err := DocPost(uid, gid, req); err == nil {
		t.Fatal("create without a key should fail")
	}
	var count int64
	if err := testDB.Model(&DocModel{}).Count(&count).Error; err != nil || count != 0 {
		t.Fatalf("rejected create left a document: count=%d error=%v", count, err)
	}
}

func TestDocumentCreateRollsBackDocumentAndPermissionOnGroupFailure(t *testing.T) {
	testDB := documentTestDB(t)
	uid, gid := seedDocumentGroup(t, testDB)
	if err := testDB.Callback().Update().Before("gorm:update").Register("test:fail_group", func(tx *gorm.DB) {
		if tx.Statement.Table == "groups" {
			tx.AddError(errors.New("injected group update failure"))
		}
	}); err != nil {
		t.Fatal(err)
	}
	req := &RequestDocPost{}
	req.Data.EncryptedKey = []byte("key")
	req.Data.CreateAt = "1700000000"
	if _, err := DocPost(uid, gid, req); err == nil {
		t.Fatal("group update failure should fail the create")
	}
	for _, model := range []interface{}{&DocModel{}, &PermissionModel{}} {
		var count int64
		if err := testDB.Model(model).Count(&count).Error; err != nil || count != 0 {
			t.Fatalf("group failure left a document or permission: count=%d error=%v", count, err)
		}
	}
}

func TestDocumentUpdateRollsBackOnPermissionFailure(t *testing.T) {
	testDB := documentTestDB(t)
	uid, gid := seedDocumentGroup(t, testDB)
	did := createDocument(t, uid, gid, m.DocContent{Title: []byte("original")}, []byte("key"))
	before := readDocument(t, testDB, did)
	failPermissionWrites(t, testDB)
	req := &RequestDocPut{UserID: uid, EncryptedKey: []byte("new-key")}
	req.Doc.Content = &m.DocContent{Title: []byte("new title"), Rich: []byte("new body"), Scales: []byte("new scales"), Level: []byte("new level")}
	if err := DocPut(gid, did, req); err == nil {
		t.Fatal("update should fail when permission write fails")
	}
	after := readDocument(t, testDB, did)
	if !bytes.Equal(after.Title, before.Title) || !bytes.Equal(after.EncryptedKey, before.EncryptedKey) || !after.UpdatedAt.Equal(before.UpdatedAt) {
		t.Fatal("failed update changed document content, key, or timestamp")
	}
	perm, err := PermissionGet(uid, ResourceTypeDoc, did)
	if err != nil || string(perm.EncryptedKey) != "key" {
		t.Fatalf("failed update changed permission key: %v", err)
	}
}

func TestDocumentFullReencryptionUpdatesBothKeys(t *testing.T) {
	testDB := documentTestDB(t)
	uid, gid := seedDocumentGroup(t, testDB)
	did := createDocument(t, uid, gid, m.DocContent{Title: []byte("original")}, []byte("key"))
	aead := testCipher(t)
	req := &RequestDocPut{UserID: uid, EncryptedKey: []byte("new-key")}
	req.Doc.Content = &m.DocContent{
		Title: encryptTestField(t, aead, "新标题"), Rich: encryptTestField(t, aead, "新正文"),
		Scales: encryptTestField(t, aead, "[]"), Level: encryptTestField(t, aead, "1"),
	}
	if err := DocPut(gid, did, req); err != nil {
		t.Fatal(err)
	}
	doc := readDocument(t, testDB, did)
	perm, err := PermissionGet(uid, ResourceTypeDoc, did)
	if err != nil || string(doc.EncryptedKey) != "new-key" || !bytes.Equal(doc.EncryptedKey, perm.EncryptedKey) {
		t.Fatalf("full re-encryption did not update both envelopes: %v", err)
	}
	assertDecrypt(t, aead, doc.Title, "新标题")
	assertDecrypt(t, aead, doc.Rich, "新正文")
	assertDecrypt(t, aead, doc.Scales, "[]")
	assertDecrypt(t, aead, doc.Level, "1")

	// Legacy/v1 records may keep the body in scales and have no rich column.
	legacyID := createDocument(t, uid, gid, m.DocContent{Title: []byte("old"), Scales: []byte("old body"), Level: []byte("old level")}, []byte("old-key"))
	req.Doc.Content.Rich = nil
	if err := DocPut(gid, legacyID, req); err != nil {
		t.Fatalf("full re-encryption with absent legacy rich should succeed: %v", err)
	}
	legacy := readDocument(t, testDB, legacyID)
	assertDecrypt(t, aead, legacy.Title, "新标题")
	assertDecrypt(t, aead, legacy.Scales, "[]")
	assertDecrypt(t, aead, legacy.Level, "1")
}

func TestDocumentRejectsUnsafeKeyChangeAndWrongOwnership(t *testing.T) {
	testDB := documentTestDB(t)
	uid, gid := seedDocumentGroup(t, testDB)
	did := createDocument(t, uid, gid, m.DocContent{Title: []byte("original"), Rich: []byte("body")}, []byte("key"))
	cases := []struct {
		name, user, group, doc string
		key                    []byte
	}{
		{"partial key rotation", uid, gid, did, []byte("different-key")},
		{"wrong owner", uuid.NewString(), gid, did, []byte("key")},
		{"missing document", uid, gid, uuid.NewString(), []byte("key")},
		{"wrong group", uid, uuid.NewString(), did, []byte("key")},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := &RequestDocPut{UserID: tc.user, EncryptedKey: tc.key}
			req.Doc.Content = &m.DocContent{Title: []byte("must not save")}
			if err := DocPut(tc.group, tc.doc, req); err == nil {
				t.Fatal("unsafe update unexpectedly succeeded")
			}
		})
	}
	doc := readDocument(t, testDB, did)
	if string(doc.Title) != "original" || string(doc.EncryptedKey) != "key" {
		t.Fatal("rejected update changed document")
	}
	// A successful update repairs the redundant document envelope from the
	// authoritative permission envelope, preserving the existing data key.
	if err := testDB.Model(&DocModel{}).Where("id = ?", did).Update("encrypted_key", []byte("stale")).Error; err != nil {
		t.Fatal(err)
	}
	req := &RequestDocPut{UserID: uid}
	req.Doc.Content = &m.DocContent{Title: []byte("safe title")}
	if err := DocPut(gid, did, req); err != nil {
		t.Fatal(err)
	}
	if got := readDocument(t, testDB, did); string(got.EncryptedKey) != "key" || string(got.Rich) != "body" {
		t.Fatal("update did not synchronize the existing key and preserve body")
	}
}

func TestDocumentRejectsMissingPermissionKey(t *testing.T) {
	testDB := documentTestDB(t)
	uid, gid := seedDocumentGroup(t, testDB)
	did := createDocument(t, uid, gid, m.DocContent{Title: []byte("original")}, []byte("key"))
	if err := testDB.Model(&PermissionModel{}).Where("resource_id = ?", did).Update("encrypted_key", []byte{}).Error; err != nil {
		t.Fatal(err)
	}
	req := &RequestDocPut{UserID: uid, EncryptedKey: []byte("new-key")}
	req.Doc.Content = &m.DocContent{Title: []byte("must not save")}
	if err := DocPut(gid, did, req); err == nil {
		t.Fatal("update with missing permission key unexpectedly succeeded")
	}
	if got := readDocument(t, testDB, did); string(got.Title) != "original" {
		t.Fatal("missing-key failure overwrote existing content")
	}
	if err := testDB.Where("resource_id = ?", did).Delete(&PermissionModel{}).Error; err != nil {
		t.Fatal(err)
	}
	if err := DocPut(gid, did, req); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("missing permission should return not-found: %v", err)
	}
}

func TestDocumentCreateRetryReturnsFirstCommittedSnapshot(t *testing.T) {
	testDB := documentTestDB(t)
	uid, gid := seedDocumentGroup(t, testDB)
	req := &RequestDocPost{CreationID: uuid.NewString()}
	req.Data.EncryptedKey = []byte("first-key")
	req.Data.Content = m.DocContent{Title: []byte("first title"), Scales: []byte("first body")}
	req.Data.CreateAt = "1700000000"
	did, err := DocPost(uid, gid, req)
	if err != nil || did != req.CreationID {
		t.Fatalf("initial create failed: id=%q, error=%v", did, err)
	}
	before := readDocument(t, testDB, did)
	req.Data.EncryptedKey = []byte("retry-key")
	req.Data.Content.Title = []byte("new title after lost response")
	req.Data.Content.Scales = []byte("new body after lost response")
	retriedID, err := DocPost(uid, gid, req)
	if err != nil || retriedID != did {
		t.Fatalf("retry did not recover original id: id=%q, error=%v", retriedID, err)
	}
	after := readDocument(t, testDB, did)
	if !bytes.Equal(after.Title, before.Title) || !bytes.Equal(after.Scales, before.Scales) || !after.UpdatedAt.Equal(before.UpdatedAt) {
		t.Fatal("retry overwrote the first committed content or timestamp")
	}
	perm, err := PermissionGet(uid, ResourceTypeDoc, did)
	if err != nil || string(perm.EncryptedKey) != "first-key" || string(after.EncryptedKey) != "first-key" {
		t.Fatalf("retry overwrote the first committed key: %v", err)
	}
	for _, model := range []interface{}{&DocModel{}, &PermissionModel{}} {
		var count int64
		if err := testDB.Model(model).Count(&count).Error; err != nil || count != 1 {
			t.Fatalf("retry duplicated document or permission: count=%d error=%v", count, err)
		}
	}
}

func TestDocumentCreateIDCannotBeReusedAcrossOwnersOrGroups(t *testing.T) {
	testDB := documentTestDB(t)
	uid, gid := seedDocumentGroup(t, testDB)
	req := &RequestDocPost{CreationID: uuid.NewString()}
	req.Data.EncryptedKey = []byte("key")
	req.Data.Content.Title = []byte("original")
	req.Data.CreateAt = "1700000000"
	did, err := DocPost(uid, gid, req)
	if err != nil {
		t.Fatal(err)
	}
	otherUID, otherGID := seedDocumentGroup(t, testDB)
	ownerUUID, err := uuid.Parse(uid)
	if err != nil {
		t.Fatal(err)
	}
	sameOwnerGroup := GroupModel{ID: uuid.New(), UID: ownerUUID, TID: uuid.New(), Name: []byte("another group"), EncryptedKey: []byte("group-key")}
	if err := testDB.Create(&sameOwnerGroup).Error; err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ name, uid, gid string }{
		{"different owner", otherUID, otherGID},
		{"different group", uid, sameOwnerGroup.ID.String()},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if id, err := DocPost(tc.uid, tc.gid, req); err == nil || id != "" || err.Error() != "document creation id unavailable" {
				t.Fatalf("creation id collision was not rejected privately: id=%q error=%v", id, err)
			}
		})
	}
	if doc := readDocument(t, testDB, did); string(doc.Title) != "original" || doc.UID != ownerUUID {
		t.Fatal("creation id collision changed the original document")
	}
}

func TestDocumentCreateRejectsInvalidCreationID(t *testing.T) {
	testDB := documentTestDB(t)
	uid, gid := seedDocumentGroup(t, testDB)
	for _, invalid := range []string{"not-a-uuid", uuid.Nil.String()} {
		req := &RequestDocPost{CreationID: invalid}
		req.Data.EncryptedKey = []byte("key")
		req.Data.CreateAt = "1700000000"
		if id, err := DocPost(uid, gid, req); err == nil || id != "" {
			t.Fatalf("invalid creation id accepted: id=%q error=%v", id, err)
		}
	}
	var count int64
	if err := testDB.Model(&DocModel{}).Count(&count).Error; err != nil || count != 0 {
		t.Fatalf("invalid creation id left a document: count=%d error=%v", count, err)
	}
}
