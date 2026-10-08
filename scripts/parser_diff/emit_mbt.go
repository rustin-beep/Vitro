package main

// emit_mbt.go：.json.mbt 真源 emit + round-trip 对拍（铺开批 2026-10-07）。
// parser digest 与 typeck 同构（节×(sources+resp_hashes) 双 StringMap）。

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"

	"vitro/scripts/jmemit"
)

const parserDigestMbt = "scripts/parser_diff/golden_digest.json.mbt"

func emitParserMbt(d parserDigestDoc) {
	raw, err := os.ReadFile(parserDigestFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "emit: 读 %s: %v\n", parserDigestFile, err)
		os.Exit(1)
	}
	names := pSortedKeys(d.Modes)
	secs := []jmemit.FlatSection{}
	for _, name := range names {
		sec := d.Modes[name]
		srcOrd := jmemit.KeyOrderOfScalars(raw, name)
		if len(srcOrd) != len(sec.Sources) {
			srcOrd = pSortedKeys(sec.Sources)
		}
		secs = append(secs, jmemit.FlatSection{
			Name: name, Sources: sec.Sources, SrcOrder: srcOrd,
			Hashes: sec.RespHashes, HashOrder: pSortedKeys(sec.RespHashes),
		})
	}
	jmemit.EmitAndVerify(parserDigestMbt, raw, func(_ map[string][]string) string {
		return jmemit.EmitSections(d.Version, d.Note, secs)
	}, func(regen []byte) int {
		var rd struct {
			Sections map[string]struct {
				Sources map[string]string `json:"sources"`
				Hashes  map[string]string `json:"hashes"`
			} `json:"sections"`
		}
		if err := json.Unmarshal(regen, &rd); err != nil {
			fmt.Fprintf(os.Stderr, "emit: 再生件解析失败: %v\n", err)
			return 1
		}
		bad := 0
		for name, sec := range d.Modes {
			r, ok := rd.Sections[name]
			if !ok {
				fmt.Fprintf(os.Stderr, "emit: 丢节 %s\n", name)
				bad++
				continue
			}
			if !pMapsEqual(sec.Sources, r.Sources) || !pMapsEqual(sec.RespHashes, r.Hashes) {
				fmt.Fprintf(os.Stderr, "emit: 漂移节 %s\n", name)
				bad++
			}
		}
		if len(rd.Sections) != len(d.Modes) {
			bad++
		}
		return bad
	})
}

func pSortedKeys[T any](m map[string]T) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}

func pMapsEqual(a, b map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if b[k] != v {
			return false
		}
	}
	return true
}
