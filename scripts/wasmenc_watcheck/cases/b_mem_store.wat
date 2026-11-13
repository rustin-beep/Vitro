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

    ;; group: StoreMem(0)
    block
      i32.const 0
      i32.const 0
      local.set 0
      local.set 1
      block
      local.get 1
      i32.const 4096
      i32.ge_u
      br_if 0
      unreachable
      end
      local.get 1
      local.get 0
      i32.store
    end
    ;; group: StoreMemByte(0)
    block
      i32.const 0
      i32.const 0
      local.set 0
      local.set 1
      block
      local.get 1
      i32.const 4096
      i32.ge_u
      br_if 0
      unreachable
      end
      local.get 1
      local.get 0
      i32.store8
    end
    ;; group: StoreMemD(0)
    block
      i32.const 0
      f64.const 0
      local.set 4
      local.set 1
      block
      local.get 1
      i32.const 4096
      i32.ge_u
      br_if 0
      unreachable
      end
      local.get 1
      local.get 4
      f64.store
    end
    ;; group: StoreMemQ(0)
    block
      i32.const 0
      i64.const 0
      local.set 3
      local.set 1
      block
      local.get 1
      i32.const 4096
      i32.ge_u
      br_if 0
      unreachable
      end
      local.get 1
      local.get 3
      i64.store
    end
  )
)
