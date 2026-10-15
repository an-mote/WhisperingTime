package minio

import (
	"context"
	"io"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// NewClient creates an independently configured client without touching the
// application singleton. Recovery verification uses separate buckets/instances.
func NewClient(cfg Config) (*MinioClient, error) {
	client, err := minio.New(cfg.Endpoint, &minio.Options{Creds: credentials.NewStaticV4(cfg.AccessKeyID, cfg.SecretAccessKey, ""), Secure: cfg.UseSSL})
	if err != nil {
		return nil, err
	}
	m := &MinioClient{client: client, bucketName: cfg.BucketName}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := m.ensureBucketExists(ctx); err != nil {
		return nil, err
	}
	return m, nil
}

func (m *MinioClient) ReadObject(ctx context.Context, name string) (io.ReadCloser, error) {
	return m.client.GetObject(ctx, m.bucketName, name, minio.GetObjectOptions{})
}

func (m *MinioClient) WriteObject(ctx context.Context, name string, r io.Reader, size int64, mime string) error {
	_, err := m.client.PutObject(ctx, m.bucketName, name, r, size, minio.PutObjectOptions{ContentType: mime})
	return err
}
