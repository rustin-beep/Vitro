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

    ;; group: Shl(0)
    block
      i32.const 0
      i32.const 0
      local.set 1
      block
      local.get 1
      i32.const 31
      i32.le_u
      br_if 0
      unreachable
      end
      local.get 1
      i32.shl
      drop
    end
    ;; group: Shr(0)
    block
      i32.const 0
      i32.const 0
      local.set 1
      block
      local.get 1
      i32.const 31
      i32.le_u
      br_if 0
      unreachable
      end
      local.get 1
      i32.shr_s
      drop
    end
    ;; group: LShr(0)
    block
      i32.const 0
      i32.const 0
      local.set 1
      block
      local.get 1
      i32.const 31
      i32.le_u
      br_if 0
      unreachable
      end
      local.get 1
      i32.shr_u
      drop
    end
    ;; group: ShlQ(0)
    block
      i64.const 0
      i64.const 0
      local.set 3
      block
      local.get 3
      i64.const 63
      i64.le_u
      br_if 0
      unreachable
      end
      local.get 3
      i64.shl
      drop
    end
    ;; group: ShrQ(0)
    block
      i64.const 0
      i64.const 0
      local.set 3
      block
      local.get 3
      i64.const 63
      i64.le_u
      br_if 0
      unreachable
      end
      local.get 3
      i64.shr_s
      drop
    end
    ;; group: LShrQ(0)
    block
      i64.const 0
      i64.const 0
      local.set 3
      block
      local.get 3
      i64.const 63
      i64.le_u
      br_if 0
      unreachable
      end
      local.get 3
      i64.shr_u
      drop
    end
  )
)
