# Portable instance archive format

WakeCanvas moves complete workshop instances between compatible installations with
a `.wakecanvas-instance` ZIP archive. Version 1 contains:

```text
wakecanvas-instance.json
CHECKSUMS
experience.sqlite
media/...
originals/...
processed/...
<other Experience-owned instance files>
```

The platform deliberately does not interpret `experience.sqlite` or other
Experience-owned files. Export is permitted only while the instance is archived,
which means its supervised runtime is stopped and its files are stable.

`wakecanvas-instance.json` records:

- `formatVersion` (`1`);
- export timestamp;
- stable instance UUID;
- Experience package ID and exact version;
- instance name and optional URL slug;
- instance configuration;
- optional participant-code digest and its session-invalidating version.

Active state and archive timestamps are not portable state. Every imported
instance is inactive and archived until an operator restores it.

`CHECKSUMS` contains lowercase SHA-256 values for the manifest and every payload
file. It does not checksum itself. Before extraction WakeCanvas rejects absolute or
traversing paths, backslashes, duplicates, links and special file types, excessive
entry counts, and excessive uncompressed sizes. It then extracts to a unique
staging directory, verifies the complete checksum set, validates metadata, and
uses atomic directory moves to enter the live instance namespace.

The receiving kiosk must already have the same Experience ID and version installed.
If the UUID exists, the operator must explicitly choose to create a copy or replace
the matching archived instance. Replacement requires typing that instance's exact
name and never operates on an active or merely stopped instance.

Archives contain participant-code hashes but never plaintext codes. They may still
contain private workshop photographs and should be handled as sensitive files.
