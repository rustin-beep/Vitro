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

    ;; group: LoadMem(0)
    block
      i32.const 0
      local.set 1
      block
      local.get 1
      i32.const 4096
      i32.ge_u
      br_if 0
      unreachable
      end
      local.get 1
      i32.load
      drop
    end
    ;; group: LoadMemByte(0)
    block
      i32.const 0
      local.set 1
      block
      local.get 1
      i32.const 4096
      i32.ge_u
      br_if 0
      unreachable
      end
      local.get 1
      i32.load8_s
      drop
    end
    ;; group: LoadMemUByte(0)
    block
      i32.const 0
      local.set 1
      block
      local.get 1
      i32.const 4096
      i32.ge_u
      br_if 0
      unreachable
      end
      local.get 1
      i32.load8_u
      drop
    end
    ;; group: LoadMemD(0)
    block
      i32.const 0
      local.set 1
      block
      local.get 1
      i32.const 4096
      i32.ge_u
      br_if 0
      unreachable
      end
      local.get 1
      f64.load
      drop
    end
    ;; group: LoadMemQ(0)
    block
      i32.const 0
      local.set 1
      block
      local.get 1
      i32.const 4096
      i32.ge_u
      br_if 0
      unreachable
      end
      local.get 1
      i64.load
      drop
    end
  )
)
