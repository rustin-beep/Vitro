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

    ;; group: Jump(99)
    block
      i32.const 99
      global.set 0
      br 0
    end
    ;; group: JumpIfZero(42)
    block
      i32.const 0
      local.set 1
      block
      local.get 1
      br_if 0
      i32.const 42
      global.set 0
      br 0
      end
      i32.const 77
      global.set 0
      br 0
    end
    ;; group: JumpIfNotZero(42)
    block
      i32.const 0
      local.set 1
      block
      local.get 1
      br_if 0
      i32.const 77
      global.set 0
      br 0
      end
      i32.const 42
      global.set 0
      br 0
    end
  )
)
