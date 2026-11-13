;; wasmenc watcheck case -- B-class overflow check (i64 intermediate, 15 instrs)
;; crosscheck: Add operand=0 (pads: [a, b] two i32)
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
      i32.const 0
      local.set 1
      i64.extend_i32_s
      local.get 1
      i64.extend_i32_s
      i64.add
      local.set 3
      (block
        local.get 3
        i32.wrap_i64
        i64.extend_i32_s
        local.get 3
        i64.eq
        br_if 0
        unreachable
      )
      local.get 3
      i32.wrap_i64
      drop
    )
  )
)
