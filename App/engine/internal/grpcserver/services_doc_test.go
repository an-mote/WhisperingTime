package grpcserver

import (
	"context"
	"testing"

	"github.com/acer-red/whisperingtime/engine/pb"
	"github.com/google/uuid"
	"google.golang.org/grpc/metadata"
)

func TestCreateDocRejectsMalformedCreationMetadata(t *testing.T) {
	for _, values := range [][]string{{""}, {uuid.NewString(), uuid.NewString()}} {
		ctx := context.WithValue(context.Background(), ctxUOIDKey, uuid.NewString())
		ctx = metadata.NewIncomingContext(ctx, metadata.MD{"document-create-id": values})
		response, err := (&Service{}).CreateDoc(ctx, &pb.CreateDocRequest{})
		if err != nil || response.GetErr() == 0 || response.GetMsg() != "invalid document creation id" {
			t.Fatalf("malformed creation metadata accepted: response=%v error=%v", response, err)
		}
	}
}
