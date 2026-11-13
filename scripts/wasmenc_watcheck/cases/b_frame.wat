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

    ;; group: GetFrameBase(0)
    block
      global.get 1
      drop
    end
    ;; group: Dup(0)
    block
      i32.const 0
      local.tee 0
      local.get 0
      drop
      drop
    end
    ;; group: Swap(0)
    block
      i32.const 0
      i32.const 0
      local.set 0
      local.set 1
      local.get 0
      local.get 1
      drop
      drop
    end
  )
)
