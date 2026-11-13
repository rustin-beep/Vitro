;; wasmenc watcheck case -- B-class triple check (neg/overflow/reserve, 35 instrs)
;; crosscheck: StackAlloc operand=0 (pad: [size] one i32; $sp = global 3)
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
      local.set 0
      (block
        local.get 0
        i32.const 0
        i32.ge_s
        br_if 0
        unreachable
      )
      local.get 0
      i32.const 3
      i32.add
      i32.const -4
      i32.and
      local.set 0
      (block
        local.get 0
        global.get $g3
        i32.le_u
        br_if 0
        unreachable
      )
      (block
        global.get $g3
        local.get 0
        i32.sub
        i32.const 4096
        i32.ge_u
        br_if 0
        unreachable
      )
      global.get $g3
      local.get 0
      i32.sub
      global.set $g3
      global.get $g3
      drop
    )
  )
)
