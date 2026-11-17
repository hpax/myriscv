<!-- Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com> -->

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

- The `mem` bus is a pass-through of the imem and dmem buses when
  targeting memory (RAM), controlled by the memory bus arbiter (in
  `myriscv.sv`).

- The `io` bus is a registered pass-through of the `dbus` when targeting
  I/O.

### SystemVerilog representation

`rtl/busif.sv` defines the shared `bus_if` interface. Its `address_bits`
parameter defaults to 32; data remains 32 bits with four byte enables.
Members use the signal names below, without a bus-name prefix:
`dbus.valid`, `imem.a`, etc.

The `initiator` and `target` modports carry reads, writes, CBOs, and
posted-operation status. `read_initiator` and `read_target` expose only
`a`, `valid`, `rdata`, and `ready`. `cache_initiator` adds incoming
invalidation signals to a read bus. `memory_initiator` and `memory_target`
carry writes and memory transaction snooping, but not CBOs. `monitor`
provides read-only access to all signals.

Optional capabilities default to disabled. Enable a capability on the
interface instance before driving its signals:

| Parameter | Signals enabled | Disabled values |
| --- | --- | --- |
| `writeable` | `wrq`, `wdata`, `wbe` | All zero (read-only) |
| `cache_ops` | `cbo` | `CBO_NONE` |
| `posted` | `busy` | Zero |
| `snoop` | `a_in`, `inval` | Zero |
| `geographical` | `inval_geo` | Zero |
| `dma` | `cpu` | One (CPU-only memory) |

For example:

```systemverilog
bus_if ibus();
bus_if #(.writeable(1'b1), .cache_ops(1'b1), .posted(1'b1)) dbus();
bus_if #(.address_bits(ram_size_bits), .writeable(1'b1),
         .snoop(1'b1)) mem();
```

Disabled fields need no connection or driver in either endpoint. Optional
controls have `tri0` pull defaults (`cpu` uses `tri1`); data and snoop
addresses use `tri`. Disabled capabilities additionally have explicit
constant drivers because Quartus does not synthesize interface pull
defaults reliably. Enabled fields must have a driver for synthesis, and
disabled fields must not be driven by an endpoint. Procedural producers
use local variables and continuous assignments to drive these nets.
Geographical invalidation also uses `a_in`; enable `snoop` when supplying
geographical addresses.

The FPGA benchmark wrapper retains scalar physical pins. Its former
`mem_addr_i`, `mem_wr`, and `mem_cpu` sidebands map to `mem.a_in`,
`mem.inval`, and `mem.cpu`, respectively. A CPU-only memory controller
leaves `dma` disabled, supplies the accepted transaction address on
`a_in`, and pulses `inval` on each memory write. These sidebands remain
independent of CPU requests so other memory agents can invalidate icache
entries. D-stage cache lookup bypasses are pipeline connections, not
standard transaction buses.

Run the interface default/override regression with
`make -C test/bench check-busif`.

## Bus specification

At the current time, there is no support for bus clocks ≠ core clocks,
burst transactions, or asynchronous transactions. Those might become
future extensions. All transactions are currently 32 bits wide.

Bit- and byte-ordering are both littleendian.

### Standard bus behavior

#### Signal descriptions

- **Signals from the initiator:**

  - `valid`: indicates that the defined output signals are valid and
    stable and constitute a transaction request. When `valid` = `0`,
    all other signals are *undefined* and *must* be ignored by the
    target. Once `valid` has been asserted, all defined signals
    (including `valid` itself) *must* be held stable until the target
    indicates that the transaction is complete (`ready` = `1`).
	- After a clock edge with `ready` = `1`, the transaction is
	  complete, and if `valid` is still asserted at the next clock edge
      it starts a new transaction. The initiator is *not* required to
	  pulse `valid` to `0` to initiate a new transaction.
	- Thus, if the initiator does not wish to initiate a new
      transaction, it *must* combinatorially deassert `valid`.

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
    *undefined* and *must* be ignored by the initiator. A clock edge with
    `ready` = `1` terminates a transaction, and the initiator is
    allowed to begin another request in the very next cycle by keeping
    `valid` asserted, otherwise it *must* combinatorially deassert
    `valid`.
	- There is no requirement to pulse `ready` to `0` if the target
	  can fulfill the new request immediately, and a target that can
	  always fulfill a request in a single cycle is
      allowed to tie `ready` to `1`.

  - `rdata`: the data read. *Undefined* if `ready` = `0` or if the
    transaction being terminated is not a read request (a write or CBO
    request.)

  - `busy`: asserted if an operation has been posted but is not yet
    globally observable (by icache, dcache, DMA, and I/O devices.)
    - Buses that only support read transactions (`ibus`, `imem`)
      inherently do not support posted transactions (since the
      acknowledgement carries the read data return) and thus have no
      `busy` signal (equivalent to `busy` being hard-wired to `0`.)
	- The target *must* assert `busy` no later than the same cycle in
      which it asserts `ready` upon accepting the posted transaction,
      and keep it asserted until *all* transactions have completed
      downstream.
	- The initiator *must not* expect that the number of assertions or
      deassertions of `busy` is related to the number of transactions
      submitted.
    - A target *may* assert `ready` to acknowledge a store or CBO request
      while keeping `busy` asserted until all its pending operations are
      all globally observable.
    - The initiator *may* request new transactions by asserting
      `valid`, and the target *may* accept any number of transactions
	  before deasserting `busy`.
	- The target *may* assert `busy` spontaneously at any time, even
      when not in response to an initiator-requested transaction.
	- If `valid` = `busy` = `0`, the bus, including all its downstream
      transactors, is considered quiescent.
	- A `fence` operation holds the pipeline until all buses are
      quiescent.
	- A `fence.i` operation will additionally restart the
	  pipeline from the fetch stage after completion.

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

  - This is transparently handled by the icache and TCM and does *not*
    apply to the `imem` bus.

#### `dbus` special cases

- **Write combining:** the initiator may combine the pending upper
  fragment of a misaligned store with the lower fragment of the
  immediately following store when they target the same 32-bit word.
  This is permitted only for addresses below `uc_base`; the resulting
  transaction has the union of both stores' byte enables, and later
  store data takes precedence for overlapping byte lanes. Targets must
  accept any byte-enable combination and must not require misaligned
  stores to appear as separate transactions.

- **Additional signals from initiator**

  - `cbo`: cache block operation. If nonzero (not `CBO_NONE`), the
    transaction is a cache block operation (`CBO_INVAL`, `CBO_CLEAN`,
    `CBO_FLUSH`). No data is returned from a cache block operation
    (`rdata` is *undefined*) and they are allowed to be posted like
    write transactions.

- **Additional signals from target**

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
