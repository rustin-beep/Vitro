;; wasmenc watcheck case (generated skeleton, human-reviewed)
(module
  (import "env" "vitro_host_call" (func $host (param i32 i32) (result i64)))
  (memory 1 1)
  (global $g0 (mut i32) (i32.const 0))
  (global $g1 (mut i32) (i32.const 0))
  (global $g2 (mut i32) (i32.const 0))
  (global $g3 (mut i32) (i32.const 0))
  (global $g4 (mut i32) (i32.const 0))
  (global $g5 (mut i64) (i64.const 0))
  (func (export "main") (local i32 i32 i32 i64 f64 f32)

    ;; group: UAdd(0)
    block
      i32.const 0
      i32.const 0
      i32.add
      drop
    end
    ;; group: USub(0)
    block
      i32.const 0
      i32.const 0
      i32.sub
      drop
    end
    ;; group: UMul(0)
    block
      i32.const 0
      i32.const 0
      i32.mul
      drop
    end
    ;; group: UDiv(0)——覆盖对账补齐（批 1b 漏网，2026-11-13）
    block
      i32.const 0
      i32.const 0
      i32.div_u
      drop
    end
    ;; group: UMod(0)——覆盖对账补齐（批 1b 漏网，2026-11-13）
    block
      i32.const 0
      i32.const 0
      i32.rem_u
      drop
    end
  )
)
