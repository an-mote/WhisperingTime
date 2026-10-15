package grpcserver

import (
	"context"
	"io"
	"path"
	"strings"
	"testing"

	"github.com/acer-red/whisperingtime/engine/pb"
	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type backupImportTestStream struct {
	grpc.ServerStream
	ctx   context.Context
	chunk *pb.BytesChunk
	err   error
	read  bool
}

func (s *backupImportTestStream) Context() context.Context { return s.ctx }
func (s *backupImportTestStream) Recv() (*pb.BytesChunk, error) {
	s.read = true
	if s.err != nil {
		return nil, s.err
	}
	if s.chunk != nil {
		v := s.chunk
		s.chunk = nil
		return v, nil
	}
	return nil, io.EOF
}
func (s *backupImportTestStream) SendAndClose(*pb.ImportGroupConfigResponse) error { return nil }

func TestBackupImportRejectsUnauthenticatedAndOversizedChunks(t *testing.T) {
	unauth := &backupImportTestStream{ctx: context.Background()}
	if err := (&Service{}).ImportGroupConfig(unauth); status.Code(err) != codes.Unauthenticated || unauth.read {
		t.Fatal("unauthenticated import accepted or read")
	}
	ctx := context.WithValue(context.Background(), ctxUOIDKey, uuid.NewString())
	oversized := &backupImportTestStream{ctx: ctx, chunk: &pb.BytesChunk{Data: make([]byte, 64*1024+1)}}
	if err := (&Service{}).ImportGroupConfig(oversized); status.Code(err) != codes.ResourceExhausted {
		t.Fatal("oversized restore chunk accepted")
	}
	broken := &backupImportTestStream{ctx: ctx, err: io.ErrUnexpectedEOF}
	if err := (&Service{}).ImportGroupConfig(broken); err != io.ErrUnexpectedEOF {
		t.Fatal("broken upload proceeded to recovery")
	}
}

func TestUploadObjectPathKeepsSameNamedImagesIndependent(t *testing.T) {
	a := uploadObjectPath("owner", "theme", "group", "document", "same.png")
	b := uploadObjectPath("owner", "theme", "group", "document", "same.png")
	if a == b {
		t.Fatal("same-named uploads overwrite the same ciphertext")
	}
	for _, p := range []string{a, b} {
		if path.Dir(p) != "owner/theme/group/document" || !strings.HasSuffix(p, "-same.png") {
			t.Fatalf("unexpected upload path %s", p)
		}
		if _, err := uuid.Parse(strings.TrimSuffix(path.Base(p), "-same.png")); err != nil {
			t.Fatal("upload lacks unique prefix")
		}
	}
	unsafe := uploadObjectPath("owner", "theme", "group", "document", "../../same.png")
	if path.Dir(unsafe) != "owner/theme/group/document" {
		t.Fatal("filename escaped object hierarchy")
	}
}
