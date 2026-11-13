;; wasmenc watcheck case -- B-class context addressing (fb+off)
;; crosscheck: LoadLocal operand=8 -> [global.get $fb; i32.const 8; i32.add; i32.load]
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
    (block
      global.get $g1
      i32.const 8
      i32.add
      i32.load
      drop
    )
  )
)
