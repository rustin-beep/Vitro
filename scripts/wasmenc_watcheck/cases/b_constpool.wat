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

    ;; group: PushConstD(0)
    block
      f64.const 1.5
      drop
    end
    ;; group: PushConstD(1)
    block
      f64.const -0.25
      drop
    end
    ;; group: PushConstQ(0)
    block
      i64.const 42
      drop
    end
    ;; group: PushConstQ(1)
    block
      i64.const -1
      drop
    end
    ;; group: TruncUByte(0)
    block
      i32.const 0
      i32.const 255
      i32.and
      drop
    end
  )
)
