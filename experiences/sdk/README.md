# WakeCanvas Experience SDK

This independent Mix project defines the stable contracts shared by the WakeCanvas
platform and installable Experience OTP applications.

It also defines the instance context passed when the platform activates one
operator-configured instance. Packages are reusable; instance configuration,
SQLite, and media paths are isolated.

It intentionally contains no platform implementation and currently has no external
dependencies. The initial contract includes declarative Experience definitions and
configuration validation. Package building, UI integration, storage, and hardware
contracts will be added only with corresponding platform implementations and ADRs.
