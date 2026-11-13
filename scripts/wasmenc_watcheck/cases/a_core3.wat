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

    ;; group: Nop(0)
    block
      nop
    end
    ;; group: PushConst(8)
    block
      i32.const 8
      drop
    end
    ;; group: Pop(0)
    block
      i32.const 0
      drop
    end
    ;; group: Not(0)——i32.eqz（覆盖对账补齐：批 1b 全量声明漏网，2026-11-13）
    block
      i32.const 0
      i32.eqz
      drop
    end
  )
)
