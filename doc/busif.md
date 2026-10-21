# Bus specification

## Address ranges

Four primary address ranges are provided, the first two of which are
optional:

- Null trap [`0`, `tcm_base`).
  - Generate a bus fault when accessed (not yet implemented).
- Tightly coupled memory (TCM) [`tcm_base`, `ram_base`).
  - Single cycle read/write memory.
  - Accessible as both instructions and data.
  - I-to-D synchronization requires a `fencei` instruction only.
- Memory (RAM) [`ram_base`, `io_base`).
  - Cacheable memory.
  - Carried over the `imem` and `dmem` buses.
  - Accessible as both instructions and data.
  - I-to-D synchronization equires a dcache flush operation
    followed by `fencei`.
  - One address bit (`car_bit`) is reserved for geographical cache
    addressing ("cache-as-ram").
    - *Additional address bits for e.g. write-through?*
- I/O [`io_base`, `-1`]
  - Not cacheable.
  - Carried over the `io` bus.
  - Accessible as data only.

## The interface buses

- The `ibus` and `dbus` buses are initiated by the core with the
  icache, dcache, and TCM as targets.

- The `dbus` also carries I/O traffic destined for the `io` bus.

  - `ibus` takes its input from the F1 stage and its output goes to
    the F2 stage.

  - `dbus` takes its input from the E stage and its output goes to the M stage.

- The `imem` and `dmem` buses are initiated by icache and dcache with
  the memory as the target, via the `mem` bus arbiter.

  - It is currently *undecided* if the `dmem` bus will carry I/O
    traffic to be split off in a latter stage or if the splitting off
    of I/O traffic will happen at an earlier point.

- The `mem` bus is a pass-through of the imem and dmem buses when
  targeting memory (RAM), controlled by the memory bus arbiter (in
  `myriscv.sv`).

- The `io` bus is a pass-through of the dbus when targeting I/O.

## Bus specification

At the current time, there is no support for bus clocks ≠ core clocks,
burst transactions, or asynchronous transactions. Those might become
future extensions. All transactions are currently 32 bits wide.

Bit- and byte-ordering are both littleendian.

### Standard bus behavior

#### Signal descriptions

- **Signals from the initiator:**

  - `valid`: indicates that the defined output signals are valid and
    stable and constitute a transaction request. When `valid` = `0`, all
    other signals are *undefined* and *must* be ignored by the
    target. Once `valid` has been asserted, the other defined signals
    *must* be held stable until the target indicates that the
    transaction is complete (`valid` = `ready` = `1`).

  - `a`: the requested transaction address. The target *may* ignore
    bits `[1:0]`; they are provided solely for the benefit of I/O
    devices that wants to control read side effects on a sub-word
    granularity. The `ibus` and thus the `imem` bus never set those bits
    and they are retained simply a convenience for simulation
    debugging.

  - `wrq`: write request. `1` for write requests, `0` for read requests.

  - `wdata`: write data. *Undefined* if `wrq` = `0`.

  - `wbe`: write byte enables. *Undefined* if `wrq` = `0`.

- **Signals from the target:**

  - `ready`: the requested transaction in complete and the output
    signals are valid and stable. When `ready` = `0` all other signals are
    *undefined* and *must* be ignored by the initiator. A cycle with
    `valid` = `ready` = `1` terminates a transaction, and the initiator is
    allowed to begin another request in the very next cycle by keeping
    valid asserted. Similarly, there is no requirement to pulse `ready`
    low if the target can fulfill the new request immediately.

  - `rdata`: the data read. *Undefined* if `wrq` = `1`.

#### Alignment

- The core transparently handles misaligned instruction fetches,
  loads, or stores, breaking them into multiple transactions if
  necessary. Other initiators may behave differently.

#### Narrow devices

(At least) the `dbus` and `io` buses support I/O devices narrower than
32 bits:

- The `a[1:0]` bits are defined from the core to be the full base
  address of the transation down to the byte level, and the core will
  replicate `wdata` across all appropriate byte lanes even if the
  corresponding `wbe` bits are not set.
  - For byte operations: all `wdata` bytes carry the same data.
  - For halfword operations to even addresses: `wdata[15:0]` and
    `wdata[31:16]` and carry the same data.
  - For halfword operations to odd addresses: `wdata[23:8]` and
  `{ wdata[7:0], wdata[31:24] }` carry the same data.
  - Split transactions due to misaligned word or halfword operations do
    *not* necessarily produce the same `wdata` output as a pair of aligned
    halfword or byte operations.
    - In the current implementation, the `wdata` bus contains the
      rotated equivalent of the aligned data of the full operation.

- Narrow devices should similarly duplicate their output across the
  `rdata` signal bus.

- There is no support for subdividing operations, thus software is
  responsible for using the proper size operations for the target
  device, or a bus adapter is necessary.

### Special cases

The following special cases apply to specific buses.

#### `ibus` special cases

- The `ibus` uniquely allows the initiator to "change its mind" and
  either deassert `valid` or change the request address before a
  transaction is complete. The target *must not* assert
  `ready` until the transaction reflecting the *current* value of `a`
  is complete.

  - This is transparently handled by the icache.

#### `dbus` special cases

- **Additional signals from initiator**

  - `cbo`: cache block operation. If nonzero (not `CBO_NONE`), the
    transaction is a cache block operation (`CBO_INVAL`, `CBO_CLEAN`,
    `CBO_FLUSH`). No data is returned from a cache block operation
    (`rdata` is *undefined*).

- **Additional signals from target**

  - `busy`: asserted if an operation has been posted but is not yet
    globally observable (by icache, dcache, and DMA).

#### `imem` special cases

- **Additional signals from target:**

  - `a_in`: the currently accessed memory address. Used
    to invalidate icache entries as a result of data writes or
    DMA. Must equal `a` while `ready` is asserted (this requirement
    might be relaxed in the future.)

  - `inval`: asserted when the icache should invalidate the line
    containing the memory address given by `a_in`.

  - `inval_geo`: asserted when the icache should invalidate the line
    geographically specified by `a_in`. Support for geographical
    icache invalidation is *optional* if the icache is guaranteed to
    start out invalidated on power on or after reset.

#### `dmem` special cases

- **Additional signals from target**

  - `busy`: asserted if an operation has been posted but is not yet
    globally observable (by icache, dcache, and DMA).
