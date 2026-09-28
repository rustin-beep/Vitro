package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// J9 锚：探针的判定面（漂移 / 无法判定的分类 + 基线校验 + 版本号解析）。
// 埋雷实跑形态见提交记录：基线副本篡改哈希 → exit 1；VENDOR_DRIFT_RAW_BASE
// 指向不可达地址 → exit 2（本文件用 httptest 关停服务器锚定同一分类逻辑）。

func TestParseVersion(t *testing.T) {
	mod := "name = \"moonbitlang/x\"\n\nversion = \"0.5.5\"\n\nlicense = \"Apache-2.0\"\n"
	if got := parseVersion(mod); got != "0.5.5" {
		t.Fatalf("version 解析: got %q want 0.5.5", got)
	}
	if got := parseVersion("name = \"x\""); got != "" {
		t.Fatalf("无 version 字段应得空串: %q", got)
	}
}

func TestSha256Hex(t *testing.T) {
	// "abc" 的 sha256 是公开已知值——锚定哈希口径本身（hex 小写）。
	if got := sha256Hex([]byte("abc")); got != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" {
		t.Fatalf("sha256 口径漂移: %s", got)
	}
}

func TestFetchClassifiesStatus(t *testing.T) {
	// 200 → statusOK 且读回 body；404 → statusNotFound（漂移通道）；500 →
	// error（无法判定通道——非 404 失败不得判上游变更）。
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/ok.txt"):
			w.Write([]byte("hello"))
		case strings.HasSuffix(r.URL.Path, "/gone.txt"):
			w.WriteHeader(http.StatusNotFound)
		default:
			w.WriteHeader(http.StatusInternalServerError)
		}
	}))
	defer srv.Close()
	client := srv.Client()

	body, st, err := fetch(client, srv.URL, "repo", "main", "ok.txt")
	if err != nil || st != statusOK || string(body) != "hello" {
		t.Fatalf("200 形态: st=%v err=%v body=%q", st, err, body)
	}
	if _, st, err := fetch(client, srv.URL, "repo", "main", "gone.txt"); err != nil || st != statusNotFound {
		t.Fatalf("404 应判 statusNotFound（漂移）: st=%v err=%v", st, err)
	}
	if _, _, err := fetch(client, srv.URL, "repo", "main", "boom.txt"); err == nil {
		t.Fatalf("500 应返 error（无法判定，非漂移）")
	}

	// 服务器关停后的连接失败 → error（无法判定，exit 2 通道）。
	srv.Close()
	if _, _, err := fetch(client, srv.URL, "repo", "main", "ok.txt"); err == nil {
		t.Fatalf("网络失败应返 error（无法判定）")
	}
}

func TestLoadBaselineRejectsBadShape(t *testing.T) {
	dir := t.TempDir()
	write := func(name, content string) string {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
		return p
	}
	// J9 ①：repo 张冠李戴（基线换成别的仓库）必须拒绝判定。
	p := write("wrong_repo.json", `{"repo":"other/repo","ref":"main","files":[{"path":"fs/fs.mbt","sha256":"aa"}]}`)
	if _, err := loadBaseline(p); err == nil || !strings.Contains(err.Error(), "张冠李戴") {
		t.Fatalf("repo 不符应拒绝: %v", err)
	}
	// J9 ②：空 files（空集不得绿）。
	p = write("empty_files.json", `{"repo":"moonbitlang/x","ref":"main","files":[]}`)
	if _, err := loadBaseline(p); err == nil || !strings.Contains(err.Error(), "空") {
		t.Fatalf("空 files 应拒绝: %v", err)
	}
	// J9 ③：ref 口径漂移（基线记 tag、探针盯 main）必须拒绝。
	p = write("wrong_ref.json", `{"repo":"moonbitlang/x","ref":"v0.5.5","files":[{"path":"fs/fs.mbt","sha256":"aa"}]}`)
	if _, err := loadBaseline(p); err == nil || !strings.Contains(err.Error(), "ref=") {
		t.Fatalf("ref 不符应拒绝: %v", err)
	}
}

func TestDriftErrorCarriesCount(t *testing.T) {
	// 漂移与无法判定的分通道锚：driftError 是唯一走 exit 1 的形态。
	de := driftError{count: 2, details: "  a\n  b"}
	if !strings.Contains(de.Error(), "2") {
		t.Fatalf("错误文本应含漂移计数: %s", de.Error())
	}
}
