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

    ;; group: StepEvent(0)
    block
      global.get 2
      i32.const 1
      i32.add
      global.set 2
    end
    ;; group: TrapBounds(0)
    block
      i32.const 0
      local.set 1
      block
      local.get 1
      i32.const 4
      i32.lt_u
      br_if 0
      unreachable
      end
      local.get 1
      drop
    end
    ;; group: TrapBounds(-3)
    block
      i32.const 0
      local.set 1
      block
      local.get 1
      i32.const 3
      i32.lt_u
      br_if 0
      unreachable
      end
      local.get 1
      drop
    end
  )
)
