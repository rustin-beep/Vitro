;; wasmenc watcheck case -- C-class ambiguity pair (bytes identical to [PushConst(-1); BitXor])
;; crosscheck: BitNot operand=0 -> emit = [i32.const -1; i32.xor]
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
      i32.const 0
      i32.const -1
      i32.xor
      drop
    )
  )
)
