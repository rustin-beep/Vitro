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

    ;; group: SplitD(0)
    block
      f64.const 0
      i64.reinterpret_f64
      local.set 3
      local.get 3
      i32.wrap_i64
      local.get 3
      i64.const 32
      i64.shr_u
      i32.wrap_i64
      drop
      drop
    end
    ;; group: SplitQ(0)
    block
      i64.const 0
      local.set 3
      local.get 3
      i32.wrap_i64
      local.get 3
      i64.const 32
      i64.shr_u
      i32.wrap_i64
      drop
      drop
    end
    ;; group: StackAlloc(0)
    block
      i32.const 0
      local.set 0
      block
      local.get 0
      i32.const 0
      i32.ge_s
      br_if 0
      unreachable
      end
      local.get 0
      i32.const 3
      i32.add
      i32.const -4
      i32.and
      local.set 0
      block
      local.get 0
      global.get 3
      i32.le_u
      br_if 0
      unreachable
      end
      block
      global.get 3
      local.get 0
      i32.sub
      i32.const 4096
      i32.ge_u
      br_if 0
      unreachable
      end
      global.get 3
      local.get 0
      i32.sub
      global.set 3
      global.get 3
      drop
    end
  )
)
