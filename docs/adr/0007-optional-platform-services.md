# ADR-0007: Optional platform services for shared local capabilities

## Status

Accepted

## Context

Experience definitions already declare static capabilities such as camera,
microphone, touch, WebGL, participant devices, and native Ports. Those declarations
allow the platform or browser to decide whether an Experience or renderer can run;
they are not callable runtime services.

Some optional functions are useful to multiple Experiences and should be configured
once per kiosk. The first is structured local-AI generation through an
operator-installed Ollama-compatible endpoint. Coupling an Experience directly to
that endpoint would expose provider URLs, duplicate health and timeout behavior,
and make provider changes require Experience upgrades.

WakeCanvas remains offline-first. A shared service must never become necessary for
the management UI, package lifecycle, kiosk startup, or an Experience that provides
a deterministic fallback.

## Decision

Introduce **Platform Services** as a separate, versioned SDK boundary. Keep the
existing `capabilities` metadata for static browser and hardware requirements.

The platform owns:

- operator configuration of service providers;
- provider health checks and visible diagnostics;
- bounded request queues, timeouts, and normalized errors;
- selection of the configured provider for a service contract; and
- injection of an opaque SDK service API into authorized Experience runtime and
  surface contexts.

Experiences declare optional service requirements and call service IDs and contract
versions through the SDK. They do not receive provider URLs or credentials and do
not depend on provider-specific response formats.

The first contract is `structured_generation` version 1. It accepts bounded text
input plus a required result schema and returns validated structured data. The first
provider is an operator-configured local Ollama endpoint. Cloud providers are out of
scope for this decision.

Service availability is optional and dynamic. Experiences must define behavior for
unavailable, timed-out, invalid, and failed responses. Collective Form uses a
deterministic interpretation fallback so its display remains operational without
AI.

Service calls do not write directly to an Experience database. An Experience owns
and persists accepted results inside its assigned instance directory and database.
The platform may retain bounded transient job state for queueing and diagnostics,
but it does not own Experience interpretation history.

An external local provider is not part of the WakeCanvas release lifecycle. Failure
or absence of that provider must not prevent the platform management UI or an active
Experience from starting. A future WakeCanvas-managed inference helper may implement
the same service contract without changing Experiences.

## Consequences

- Shared providers are installed and configured once per kiosk.
- Experiences remain independent of Ollama and other provider implementations.
- The SDK gains discovery and invocation contracts in addition to declarative
  capability metadata.
- The platform needs service configuration, health, queueing, diagnostics, and
  request validation.
- AI-enabled Experiences require deterministic fallbacks and cannot assume a
  provider is available.
- Local provider performance and model compatibility remain deployment concerns,
  but do not change the Experience contract.
