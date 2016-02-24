/*
 * kernel/init/bootparams.swift
 *
 * Created by Simon Evans on 24/12/2015.
 * Copyright © 2015, 2016 Simon Evans. All rights reserved.
 *
 * Initial setup for available physical memory etc
 * Updated to handle multiple data source eg BIOS, EFI
 *
 */

let kb: UInt = 1024
let mb: UInt = 1048576

// These memory types are just the EFI ones, the BIOS ones are
// actually a subset so these definitions cover both cases
enum MemoryType: UInt32 {
    case Reserved    = 0            // Not usable
    case LoaderCode                 // Usable
    case LoaderData                 // Usable
    case BootServicesData           // Usable
    case BootServicesCode           // Usable
    case RuntimeServicesCode        // Needs to be preserved / Not usable
    case RuntimeServicesData        // Needs to be preserved / Not usable
    case Conventional               // Usable (RAM)
    case Unusable                   // Unusable (RAM with errors)
    case ACPIReclaimable            // Usable after ACPI enabled
    case ACPINonVolatile            // Needs to be preserved / Not usable
    case MemoryMappedIO             // Umusable
    case MemoryMappedIOPortSpace    // Unusable

    // OS defined values
    case Hole        = 0x80000000   // Used for holes in the map to keep ranges contiguous
    case PageMap     = 0x80000001   // Temporary page maps setup by the boot loader
    case BootData    = 0x80000002   // Other temporary data created by boot code inc BootParams
    case Kernel      = 0x80000003   // The loaded kernel + data + bss
    case FrameBuffer = 0x80000004   // Framebuffer address if it is the top of the address space
}


struct MemoryEntry: CustomStringConvertible {
    let type: MemoryType
    let start: PhysAddress
    let size: UInt

    var description: String {
        let str = (size >= mb) ? String.sprintf(" %6uMB  ", size / mb) :
                String.sprintf(" %6uKB  ", size / kb)

        return String.sprintf("%12X - %12X \(str) \(type)", start, start + size - 1)
    }
}


// The boot parameters also contain information about the framebuffer if present
// so that the TTY driver can be initialised before PCI scanning has taken place
struct FrameBufferInfo: CustomStringConvertible {
    let address:       UInt
    let size:          UInt
    let width:         UInt32
    let height:        UInt32
    let pxPerScanline: UInt32
    let depth:         UInt32
    let redShift:      UInt8
    let redMask:       UInt8
    let greenShift:    UInt8
    let greenMask:     UInt8
    let blueShift:     UInt8
    let blueMask:      UInt8


    init(fb: frame_buffer) {
        address = fb.address.ptrToUint
        size = UInt(fb.size)
        width = fb.width
        height = fb.height
        pxPerScanline = fb.px_per_scanline
        depth = fb.depth
        redShift = fb.red_shift
        redMask = fb.red_mask
        greenShift = fb.green_shift
        greenMask = fb.green_mask
        blueShift = fb.blue_shift
        blueMask = fb.blue_mask

    }


    var description: String {
        var str = String.sprintf("Framebuffer: %dx%d bpp: %d px per line: %d addr:%p size: %lx\n",
            width, height, depth, pxPerScanline, address,  size);
        str += String.sprintf("Red shift:   %2d Red mask:   %x\n", redShift, redMask);
        str += String.sprintf("Green shift: %2d Green mask: %x\n", greenShift, greenMask);
        str += String.sprintf("Blue shift:  %2d Blue mask:  %x\n", blueShift, blueMask);

        return str
    }
}


protocol BootParamsData {
    var memoryRanges: [MemoryEntry] { get }
    var source: String { get }
    var frameBufferInfo: FrameBufferInfo? { get }
    var kernelPhysAddress: PhysAddress { get }
    func findRSDP() -> UnsafePointer<RSDP1>?
}


private func readSignature(address: PhysAddress) -> String? {
    let signatureSize = 8
    let membuf = MemoryBufferReader(address, size: signatureSize)
    guard let sig = try? membuf.readASCIIZString(maxSize: signatureSize) else {
        return nil
    }
    return sig
}


/*
 * The boot parameters are parsed in two stages:
 * 1. Read the data in the {bios,efi}_boot_params table and save
 * 2. Parse the tables pointed to by the data in step 1
 *
 * This is required becuase step 2 requires some pages to be mapped in
 * setupMM(), but setupMM() requires some of the data from step1.
 */

struct BootParams {
    private static var params: BootParamsData?
    static let memoryRanges = BootParams.getRanges()
    static var source: String { return params == nil ? "" : params!.source }
    static var frameBufferInfo: FrameBufferInfo? { return params?.frameBufferInfo }
    static var highestMemoryAddress: PhysAddress {
        let lastEntry = memoryRanges[memoryRanges.count - 1]
        return lastEntry.start + lastEntry.size - 1
    }

    static var kernelAddress: PhysAddress {
        guard params != nil else {
            koops("Cant find kernel physical address in BootParams memory ranges")
        }
        return params!.kernelPhysAddress
    }


    static func parse(bootParamsAddr: UInt) {
        kprintf("parsing bootParams @ 0x%lx\n", bootParamsAddr)
        if (bootParamsAddr == 0) {
            koops("bootParamsAddr is null")
        }
        guard let signature = readSignature(bootParamsAddr) else {
            koops("Cant find boot params signature")
        }
        print("signature: \(signature)");

        if (signature == "BIOS") {
            print("Found BIOS boot params")
            params = BiosBootParams(bootParamsAddr: bootParamsAddr)
        } else if (signature == "EFI") {
            print("Found EFI boot params")
            params = EFIBootParams(bootParamsAddr: bootParamsAddr)
        } else {
            print("Found unknown boot params: \(signature)")
            stop()
        }
        guard params != nil else {
            koops("BiosBootParams returned null")
        }
    }


    static func getRanges() -> [MemoryEntry] {
        var ranges = params!.memoryRanges

        findHoles(&ranges)
        guard ranges.count > 0 else {
            koops("No memory found")
        }

        // Find the last range. If it doesnt cover the frame buffer
        // then add that in as an extra range at the end
        let lastEntry = ranges[ranges.count-1]
        let address = lastEntry.start + lastEntry.size - 1
        if (frameBufferInfo != nil && address < frameBufferInfo!.address) {
            ranges.append(MemoryEntry(type: .FrameBuffer, start: frameBufferInfo!.address,
                    size: frameBufferInfo!.size))
        }

        for m in ranges {
            if (m.type == .BootServicesCode || m.type == .BootServicesData) {
                continue
            }
            print("\(params!.source): \(m)")
        }

        return ranges
    }


    static func findRSDP() -> UnsafePointer<RSDP1>? {
        return params?.findRSDP()
    }


    // Find any holes in the memory ranges and add a fake range. This
    // allows finding gaps later on for MMIO space etc
    private static func findHoles(inout ranges: [MemoryEntry]) {
        var addr: UInt = 0
        sortRanges(&ranges)
        for entry in ranges {
            if addr < entry.start {
                let size = entry.start - addr
                ranges.append(MemoryEntry(type: MemoryType.Hole, start: addr,
                        size: size))
            }
            addr = entry.start + entry.size
        }
        sortRanges(&ranges)
    }


    private static func sortRanges(inout ranges: [MemoryEntry]) {
        ranges.sortInPlace({
            $0.start < $1.start
        })
    }
}


// BIOS data from boot/memory.asm
struct BiosBootParams: BootParamsData, CustomStringConvertible {
    enum E820Type: UInt32 {
    case RAM      = 1
    case RESERVED = 2
    case ACPI     = 3
    case NVS      = 4
    case UNUSABLE = 5
    }


    struct E820MemoryEntry: CustomStringConvertible {
        let baseAddr: UInt64
        let length: UInt64
        let type: UInt32

        var description: String {
            var desc = String.sprintf("%12X - %12X %4.4X", baseAddr, baseAddr + length - 1, type)
            let size = UInt(length)
            if (size >= mb) {
                desc += String.sprintf(" %6uMB  ", size / mb)
            } else {
                desc += String.sprintf(" %6uKB  ", size / kb)
            }
            desc += String(E820Type.init(rawValue: type)!)

            return desc
        }


        private func toMemoryEntry() -> MemoryEntry? {
            guard let e820type = E820Type(rawValue: self.type) else {
                print("Invalid memory type: \(self.type)")
                return nil
            }
            var mtype: MemoryType

            switch (e820type) {
            case .RAM:      mtype = MemoryType.Conventional
            case .RESERVED: mtype = MemoryType.Reserved
            case .ACPI:     mtype = MemoryType.ACPIReclaimable
            case .NVS:      mtype = MemoryType.ACPINonVolatile
            case .UNUSABLE: mtype = MemoryType.Unusable
            }

            return MemoryEntry(type: mtype, start: PhysAddress(self.baseAddr),
                size: UInt(self.length))
        }
    }


    private let RSDP_SIG: StaticString = "RSD PTR "
    private let e820MapAddr: UInt
    private let e820Entries: UInt

    let source = "E820"
    var memoryRanges: [MemoryEntry] { return parseE820Table() }
    var frameBufferInfo: FrameBufferInfo? = nil
    var kernelPhysAddress: PhysAddress = 0

    var description: String {
        return "BiosBootParams has \(memoryRanges.count) ranges"
    }


    init?(bootParamsAddr: UInt) {
        let sig = readSignature(bootParamsAddr)
        if sig == nil || sig! != "BIOS" {
            print("boot_params are not BIOS")
            return nil
        }
        let membuf = MemoryBufferReader(bootParamsAddr,
            size: strideof(bios_boot_params))
        membuf.offset = 8       // skip signature
        do {
            // FIXME: use bootParamsSize to size a buffer limit
            let bootParamsSize: UInt = try membuf.read()
            guard bootParamsSize > 0 else {
                print("bootParamsSize = 0")
                return nil
            }
            kernelPhysAddress = try membuf.read()
            printf("bootParamsSize = %ld kernelPhysAddress: %p\n", bootParamsSize,
                kernelPhysAddress)

            e820MapAddr = try membuf.read()
            e820Entries = try membuf.read()
        } catch {
            koops("Cant read BIOS boot params")
        }
    }


    // FIXME - still needs to check for overlapping regions
    private func parseE820Table() -> [MemoryEntry] {
        guard e820Entries > 0 && e820MapAddr > 0 else {
            koops("e820 map is empty")
        }
        var ranges: [MemoryEntry] = []
        ranges.reserveCapacity(Int(e820Entries))
        let buf = MemoryBufferReader(e820MapAddr,
            size: strideof(E820MemoryEntry) * Int(e820Entries))
        for _ in 0..<e820Entries {
            if let entry: E820MemoryEntry = try? buf.read() {
                print(entry)
                if let memEntry = entry.toMemoryEntry() {
                    ranges.append(memEntry)
                }
            }
        }

        guard ranges.count > 0 else {
            koops("Cant find any memory in the e820 map")
        }

        let size = _kernel_end_addr() - _kernel_start_addr()
        printf("Kernel size: %lx\n", size)
        ranges.append(MemoryEntry(type: .Kernel, start: kernelPhysAddress,
                size: size))

        return ranges
    }


    // Root System Description Pointer
    func findRSDP() -> UnsafePointer<RSDP1>? {
        if let ebda = getEBDA() {
            printf("ACPI: EBDA: %#8.8lx len: %#4.4lx\n", ebda.baseAddress, ebda.count)
            if let rsdp = scanForRSDP(ebda) {
                return rsdp
            }
        }
        let upper = getUpperMemoryArea()
        printf("ACPI: Upper: %#8.8lx len: %#4.4lx\n", upper.baseAddress, upper.count)
        return scanForRSDP(upper)
    }


    private func getEBDA() -> ScanArea? {
        let ebdaRegion: UnsafeBufferPointer<UInt16> = mapPhysicalRegion(0x40E, size: 1)
        let ebda = ebdaRegion[0] //UInt16(msb: ebdaRegion[1], lsb: ebdaRegion[0])
        // Convert realmode segment to linear address
        let rsdpAddr = UInt(ebda) * 16

        if rsdpAddr > 0x400 {
            let region: ScanArea = mapPhysicalRegion(rsdpAddr, size: 1024)
            return region
        } else {
            return nil
        }
    }


    private func getUpperMemoryArea() -> ScanArea {
        let region: ScanArea = mapPhysicalRegion(0xE0000, size: 0x20000)
        return region
    }


    private func scanForRSDP(area: ScanArea) -> UnsafePointer<RSDP1>? {
        assert(RSDP_SIG.byteSize != 0)
        assert(RSDP_SIG.isASCII)

        for idx in 0.stride(to: area.count - strideof(RSDP1), by: 16) {
            if memcmp(RSDP_SIG.utf8Start, area.baseAddress + idx, RSDP_SIG.byteSize) == 0 {
                let region: UnsafePointer<RSDP1> = area.regionPointer(idx)
                return region
            }
        }

        return nil
    }
}


struct EFIBootParams: BootParamsData {
    typealias EFIPhysicalAddress = UInt
    typealias EFIVirtualAddress = UInt

    // Physical layout in memory
    struct EFIMemoryDescriptor: CustomStringConvertible {
        private let type: MemoryType
        private let padding: UInt32
        private let physicalStart: EFIPhysicalAddress
        private let virtualStart: EFIVirtualAddress
        private let numberOfPages: UInt64
        private let attribute: UInt64

        var description: String {
            let size = UInt(numberOfPages) * PAGE_SIZE
            let endAddr = physicalStart + size - 1
            return String.sprintf("%12X - %12X %8.8X \(type)", physicalStart,
                endAddr, size)
        }


        init?(descriptor: MemoryBufferReader) {
            let offset = descriptor.offset
            do {
                guard let dt = MemoryType(rawValue: try descriptor.read()) else {
                    throw ReadError.InvalidData
                }
                type = dt
                padding = try descriptor.read()
                physicalStart = try descriptor.read()
                virtualStart = try descriptor.read()
                numberOfPages = try descriptor.read()
                attribute = try descriptor.read()
            } catch {
                printf("Cant read descriptor at offset: %d\n", offset)
                return nil
            }
        }

    }


    struct EFIConfigTableEntry {
        let guid: efi_guid_t
        let table: UnsafePointer<Void>
    }


    private let configTableCount: UInt
    private let configTablePtr: UnsafePointer<efi_config_table_t>
    private let memoryMapAddr: VirtualAddress
    private let memoryMapSize: UInt
    private let descriptorSize: UInt

    let source = "EFI"
    var memoryRanges: [MemoryEntry] { return parseMemoryMap() }
    var frameBufferInfo: FrameBufferInfo?
    var kernelPhysAddress: PhysAddress = 0


    init?(bootParamsAddr: UInt) {
        let sig = readSignature(bootParamsAddr)
        if sig == nil || sig! != "EFI" {
            print("boot_params are not EFI")
            return nil
        }
        let membuf = MemoryBufferReader(bootParamsAddr,
            size: strideof(efi_boot_params))
        membuf.offset = 8       // skip signature
        do {
            let bootParamsSize: UInt = try membuf.read()
            guard bootParamsSize > 0 else {
                print("bootParamsSize = 0")
                return nil
            }
            kernelPhysAddress = try membuf.read()

            printf("bootParamsSize = %ld kernelPhysAddress: %p\n",
                bootParamsSize, kernelPhysAddress)

            memoryMapAddr = try membuf.read()
            memoryMapSize = try membuf.read()
            descriptorSize = try membuf.read()
            print("reading frameBufferInfo")
            frameBufferInfo = FrameBufferInfo(fb: try membuf.read())
            print(frameBufferInfo)
            configTableCount = try membuf.read()
            print("reading ctp")
            configTablePtr = try membuf.read()
            printf("configTableCopunt: %ld configTablePtr: %p\n",
                configTableCount, configTablePtr)
        } catch {
            koops("Cant read memory map settings")
        }
    }


    private func parseMemoryMap() -> [MemoryEntry] {
        let descriptorCount = memoryMapSize / descriptorSize

        var ranges: [MemoryEntry] = []
        ranges.reserveCapacity(Int(descriptorCount))
        let descriptorBuf = MemoryBufferReader(memoryMapAddr,
            size: Int(memoryMapSize))

        for i in 0..<descriptorCount {
            descriptorBuf.offset = Int(descriptorSize * i)
            guard let descriptor = EFIMemoryDescriptor(descriptor: descriptorBuf) else {
                print("Failed to read descriptor")
                continue
            }
            //descriptors.append(descriptor)
            let entry = MemoryEntry(type: descriptor.type,
                start: descriptor.physicalStart,
                size: UInt(descriptor.numberOfPages) * PAGE_SIZE)
            ranges.append(entry)
        }

        return ranges
    }


    let guidACPI1 = efi_guid_t(data1: 0xeb9d2d30, data2: 0x2d88, data3: 0x11d3,
        data4: (0x9a, 0x16, 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d))


        private func matchGUID(guid1: efi_guid_t, _ guid2: efi_guid_t) -> Bool {
        return (guid1.data1 == guid2.data1) && (guid1.data2 == guid2.data2)
        && (guid1.data3 == guid2.data3)
        && guid1.data4.0 == guid2.data4.0 && guid1.data4.1 == guid2.data4.1
        && guid1.data4.2 == guid2.data4.2 && guid1.data4.3 == guid2.data4.3
        && guid1.data4.4 == guid2.data4.4 && guid1.data4.5 == guid2.data4.5
        && guid1.data4.6 == guid2.data4.6 && guid1.data4.7 == guid2.data4.7
    }

    private func printGUID(guid: efi_guid_t) {
        printf("EFI: { %#8.8x, %#8.4x, %#4.4x, { %#2.2x,%#2.2x,%#2.2x,%#2.2x,%#2.2x,%#2.2x,%#2.2x,%#2.2x }}\n",
            guid.data1, guid.data2, guid.data3, guid.data4.0, guid.data4.1, guid.data4.2, guid.data4.3,
            guid.data4.4, guid.data4.5, guid.data4.6, guid.data4.7)
    }


    // Root System Description Pointer
    func findRSDP() -> UnsafePointer<RSDP1>? {
        var match: UnsafePointer<RSDP1>?
        for entry in parseConfigTables() {
            printGUID(entry.guid)
            if matchGUID(entry.guid, guidACPI1) {
                match = ptrFromPhysicalPtr(UnsafePointer<RSDP1>(entry.table))
            }
        }

        return match
    }


    private func parseConfigTables() -> [EFIConfigTableEntry] {
        var entries: [EFIConfigTableEntry] = []
        let tables: UnsafeBufferPointer<efi_config_table_t> =
            mapPhysicalRegion(configTablePtr, size: Int(configTableCount))

        for table in tables {
            let entry = EFIConfigTableEntry(guid: table.vendor_guid,
                table: table.vendor_table)
            entries.append(entry)
        }

        return entries
    }

}
