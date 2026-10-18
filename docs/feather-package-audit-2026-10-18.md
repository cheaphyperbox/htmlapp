# Feather package audit — 2026-10-18

The user supplied the Feather-signed HTMLApp IPA and installation screenshots. This report contains findings only; the IPA, provisioning profile, certificate material, device identifiers, and provider-specific identifiers are not committed.

## Verified package findings

- Both main app and HTMLAppWidgets.appex are present.
- Both Mach-O embedded XML entitlement blobs list the same five provider-assigned App Groups.
- Neither entitlement blob includes group.com.mekabrine.htmlapp, which the current app and extension request.
- The main app embedded provisioning profile lists those same five provider groups, not HTMLApp's original group. The provider therefore DOES supply App Group entitlements; lack of all App Group support is disproven for this package.
- Only the main app contains embedded.mobileprovision; the extension does not.
- Both binaries carry the same application-identifier entitlement. Its suffix matches neither bundle's CFBundleIdentifier.
- Both binaries carry the same team identifier.
- The main profile CMS content was decoded with OpenSSL signature-integrity checking and -noverify. Apple trust-chain validation, revocation, installed profile state, and effective running-process entitlements were not verified.

The screenshots show the extension enabled and Remove Provisioning disabled. Those UI settings do not establish the contents or authorization of the resulting extension signature.

## Interpretation

The requested-group/signature mismatch is a concrete cause of the current shared-container lookup failure. The same failure when installing the Feather build on the previously working iPhone is consistent with the package/signing path, rather than an iPad-only rendering failure.

Changing Swift to request a provider group could address this specific lookup mismatch, but does not by itself validate extension provisioning or demonstrate that both installed processes can access it. Do not silently choose an arbitrary provider group: confirm its intended membership and allocation before placing user snapshots there. App Groups intentionally share data with other members; a subdirectory is not a new sandbox boundary.

## Required signing evidence

Obtain an appropriate provisioning setup for distinct main-app and widget-extension App IDs, both authorized for one agreed App Group under the same signing team. Confirm the provider's intended bundle-ID mapping and whether the chosen group is allocated to this app pair. If different bundle IDs are required, plan data-preserving migration before changing identifiers.

A private signing key or certificate ZIP is not needed to inspect these authorizations. Separate .mobileprovision files or a corrected signed IPA suffice for the next audit.

## Build decision

No replacement IPA is labelled fixed or universal on the basis of this audit. Editing the supplied signed executable invalidates its signature; rebuilding cannot grant a group absent from the authorized signing setup. One reusable base IPA may support multiple properly provisioned installations, but cannot guarantee widgets under arbitrary re-signing. Keep the known-working TrollStore build available while Feather provisioning is resolved.
