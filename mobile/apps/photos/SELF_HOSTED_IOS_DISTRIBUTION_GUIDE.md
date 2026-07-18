# Self-Hosted iOS Closed-Beta Operations

This is the operator runbook for distributing the configurable Ente Photos iOS
application to the private `trusted-ios-testers` group through Firebase App
Distribution and Apple Ad Hoc provisioning. It covers release preparation,
publication, device authorization, tester access, updates, removal, and
recovery. For toolchain and signing setup, use the
[mobile build guide](SELF_HOSTED_BUILD_GUIDE.md).

The workflow distributes only the iOS bundle
`me.vanton.ente.photos.selfhosted`. It does not add a Firebase runtime SDK,
publish through TestFlight or the App Store, expose the private server to the
internet, or distribute the Android application.

## 1. Trust boundaries and safety rules

Five independent systems grant different kinds of access:

| System | Grants | Does not grant |
|---|---|---|
| Firebase App Distribution | Invitation, device-registration flow, IPA delivery, and update notifications | Apple device authorization, Tailscale connectivity, or a Museum account |
| Apple Developer Program | App ID, signing certificate, registered devices, and installable Ad Hoc profile | Firebase release access, private network access, or Museum authentication |
| iOS Developer Mode | Permission to launch an Ad Hoc application on iOS 16 or later | Device inclusion in the profile or access to any service |
| Tailscale | Private network access to Museum and object storage | Firebase delivery, Apple authorization, or Museum authentication |
| Museum | An individual encrypted-data account and server session | IPA delivery, Apple device authorization, or private network routing |

Onboard and offboard each tester in every applicable system. Removing a tester
from Firebase does not uninstall an IPA. Excluding a device from a future Ad
Hoc profile does not revoke an already installed build. Removing only
Tailscale access does not remove the Firebase invitation or Museum account.

Always follow these rules:

- Keep tester email addresses, Apple Team IDs, device names and identifiers,
  provisioning profiles, certificate private keys, Firebase or Tailscale invite
  links, access tokens, server credentials, account recovery material, and
  signing inputs out of Git, release notes, public issue trackers, and
  repository screenshots.
- Treat Firebase registration profiles, exported Apple device lists, and Ad Hoc
  provisioning profiles as private because they carry device identifiers.
- Give every person their own Google, Tailscale, and Museum identity. Do not
  share the owner's accounts.
- Never run `firebase login:list --json`; a Firebase CLI version used during
  provisioning printed reusable OAuth material through that command. Verify
  access with a harmless resource query instead.
- Never publish from a dirty or unpushed source commit. Never edit, replace,
  rename, or make a prepared IPA or manifest writable.
- Do not use Firebase's temporary binary-download URL as a durable archive. It
  expires, while the local prepared IPA, manifest, and publication receipt are
  the release evidence.
- Do not use this invitation-only Ad Hoc workflow as public distribution. Every
  receiving iPhone must be registered with Apple and included in the embedded
  provisioning profile.

## 2. Private operator inputs

Set these values locally. The examples are placeholders, not configuration to
commit:

```sh
export ENTE_SELF_HOSTED_ENDPOINT="https://museum-host.tailnet-name.ts.net"
export ENTE_OBJECT_STORAGE_HEALTH_URL="https://museum-host.tailnet-name.ts.net:8443/minio/health/live"
export ENTE_SERVER_DIR="/absolute/path/to/private/quickstart"

export FIREBASE_CLI="/absolute/path/to/firebase"
export ENTE_FIREBASE_PROJECT_ID="your-firebase-project-id"
export ENTE_FIREBASE_IOS_APP_ID="your-firebase-ios-app-id"

export ENTE_IOS_DISTRIBUTION_TEAM="YOURTEAMID"
export ENTE_IOS_ADHOC_PROFILE="/absolute/private/path/Ente_Photos_SelfHosted_Ad_Hoc.mobileprovision"
export ENTE_IOS_EXPECTED_DEVICE_COUNT="1"
export ENTE_IOS_MARKETING_VERSION="1.0.0"
export ENTE_IOS_BUILD_NUMBER="1"

export ENTE_IOS_RELEASE_OUTPUT_DIR="/absolute/path/to/prepared-ios-releases"
export ENTE_FIREBASE_RELEASE_RECEIPT_DIR="/absolute/path/to/firebase-ios-receipts"
```

The server directory, profile, release directories, Firebase credentials, and
Apple values stay outside this repository. The Firebase project and App ID are
not secrets, but keeping them local prevents the public fork from becoming
operationally bound to one Firebase project.

Protect any reusable local environment file and its parent directory:

```sh
chmod 700 "/absolute/path/to/private-config-directory"
chmod 600 "/absolute/path/to/private-config-directory/distribution.env"
```

Confirm the CLI can see the intended project without printing authentication
state:

```sh
"$FIREBASE_CLI" projects:list
"$FIREBASE_CLI" appdistribution:groups:list \
  --project "$ENTE_FIREBASE_PROJECT_ID"
```

The second command must show the stable alias `trusted-ios-testers`.

## 3. Prepare and publish one release

### 3.1 Check the server before building

Do not publish an application update to compensate for a server outage. From
the private quickstart directory, confirm the containers are running:

```sh
cd "$ENTE_SERVER_DIR"
docker compose ps
```

From a Tailscale-connected client, verify Museum's public health contract:

```sh
curl --fail --silent --show-error "$ENTE_SELF_HOSTED_ENDPOINT/ping"
```

The response must be successful JSON whose `message` is `pong`. Verify the
object-storage route separately because Museum returns signed upload and
download URLs for that origin:

```sh
curl --fail --silent --show-error "$ENTE_OBJECT_STORAGE_HEALTH_URL"
```

Also confirm the HTTPS certificate is trusted and the private hostname resolves
from the target network. A reachable Tailscale address with an HTTP `502` from
`/ping` points to the server or proxy layer, not an application build.

### 3.2 Confirm Apple signing and device scope

Before preparing a release, confirm in Apple **Certificates, Identifiers &
Profiles** that:

- the explicit App ID is `me.vanton.ente.photos.selfhosted`;
- the intended Apple Distribution certificate remains active and its private
  key is available in the local login Keychain;
- every intended iPhone is enabled in **Devices**;
- the manual Ad Hoc profile names the exact App ID, intended distribution
  certificate, and only the currently authorized devices; and
- the profile and certificate will remain valid for the acceptance window.

Set `ENTE_IOS_EXPECTED_DEVICE_COUNT` to the exact number of devices in the
downloaded profile. Do not record their identifiers in a shell transcript or
repository file. The guarded preparation command independently decodes and
checks the profile before building.

### 3.3 Prepare the immutable release

From `mobile/apps/photos`, confirm the intended source is committed, pushed to
the fork, and reachable through `origin`:

```sh
git status --short
git branch -r --contains HEAD
```

The first command must print nothing. The second must include an `origin/*`
reference. Confirm all private inputs in section 2, choose a build number higher
than every prior guarded iOS publication, then run:

```sh
./scripts/prepare_self_hosted_ios_release.sh \
  --output-dir "$ENTE_IOS_RELEASE_OUTPUT_DIR"
```

Copy the exact manifest path printed by the command. Do not select a manifest
through a `latest` symlink or wildcard:

```sh
export ENTE_IOS_RELEASE_MANIFEST="/absolute/path/to/the-printed-release.manifest.json"
```

Review the adjacent read-only IPA and JSON manifest. Confirm at least:

- bundle `me.vanton.ente.photos.selfhosted`;
- intended marketing version and increasing `CFBundleVersion`;
- intended compiled HTTPS Museum origin;
- source commit and public fork commit URL;
- expected Apple team, authorized-device count, certificate fingerprint and
  profile validity without exposing their private values;
- no application extension, debug entitlement, application group, push,
  associated-domain, or iCloud entitlement;
- arm64 application binaries; and
- IPA SHA-256 and read-only paths outside Git.

### 3.4 Run the non-mutating publication preflight

```sh
./scripts/publish_self_hosted_ios_release.sh \
  --manifest "$ENTE_IOS_RELEASE_MANIFEST" \
  --receipt-dir "$ENTE_FIREBASE_RELEASE_RECEIPT_DIR" \
  --firebase-project "$ENTE_FIREBASE_PROJECT_ID" \
  --firebase-app "$ENTE_FIREBASE_IOS_APP_ID" \
  --preflight-only
```

The command must end with `Preflight passed. No Firebase upload was performed.`
It re-audits the exact IPA, checks prior guarded receipts for a non-increasing
build number, and verifies the active Firebase iOS bundle and
`trusted-ios-testers` group.

### 3.5 Add or review testers

Prefer the Firebase console's **App Distribution > Testers & Groups** page when
handling human identities. Add the intended people to `trusted-ios-testers` and
verify the group contains no unexpected identities. Do not put the list in a
repository file.

The equivalent CLI command is available when appropriate for the operator's
private shell:

```sh
"$FIREBASE_CLI" appdistribution:testers:add "<tester-email>" \
  --group-alias trusted-ios-testers \
  --project "$ENTE_FIREBASE_PROJECT_ID"
```

A new tester cannot install the current Ad Hoc IPA until their iPhone is
registered with Firebase and Apple and a later IPA embeds a refreshed profile.
Use section 4 for that onboarding loop.

### 3.6 Publish the audited bytes

Optional operator-visible notes belong in a local text file. Do not include
secrets, tester identities, device details, private invitation links, or
recovery material. The command generates the version, IPA hash, exact AGPL
source commit, and commit-pinned build-instructions link automatically.

Run the same command without `--preflight-only`:

```sh
./scripts/publish_self_hosted_ios_release.sh \
  --manifest "$ENTE_IOS_RELEASE_MANIFEST" \
  --receipt-dir "$ENTE_FIREBASE_RELEASE_RECEIPT_DIR" \
  --firebase-project "$ENTE_FIREBASE_PROJECT_ID" \
  --firebase-app "$ENTE_FIREBASE_IOS_APP_ID"
```

Review every summary field. Type the displayed `PUBLISH <release-id>` value
exactly only when the IPA, source, server, Apple scope, Firebase app, and group
are correct. The command rechecks the files, receipt ledger, native IPA, and
Firebase registration after confirmation; uploads the unchanged IPA once; and
writes a read-only `<release-id>.firebase-ios-release.json` receipt outside
Git.

### 3.7 Reconcile Firebase and the receipt

After success:

1. Open the receipt's Firebase console URL and confirm the displayed marketing
   version, build number, release notes, and `trusted-ios-testers`
   distribution.
2. Confirm the release notes contain the exact public source commit URL.
3. Confirm the receipt's IPA SHA-256 matches the prepared manifest.
4. Confirm Firebase shows the intended testers as invited or accepted; later,
   confirm device-registration and download state for acceptance tests.
5. Preserve the prepared IPA, manifest, and receipt together outside Git.

If the command writes `.firebase-ios-attempt-*.json`, Firebase may have
accepted the binary before a later step failed. Inspect the attempt record and
Firebase console before any retry. Do not assume a nonzero exit or missing CLI
reference means no mutation.

## 4. Authorize and onboard an iPhone

### 4.1 Accept Firebase and register the device

The tester must perform the first acceptance on the iPhone they will use:

1. Open the Firebase invitation email in **Safari on that iPhone**. Sign in
   with the Google account intended for this beta and accept the invitation.
   An invitation can be accepted only once; the operator should privately
   verify which Google identity accepted it.
2. On the application page, tap **Register device**.
3. Allow Firebase to download its configuration profile, then install that
   profile through the iOS Settings application when prompted.
4. Return to the Firebase App Distribution web clip and confirm that device
   registration completed.

The Firebase profile collects the iPhone's unique device identifier and adds
the App Distribution web clip. It does not authorize the application by
itself. Keep the registration email and exported device list private.

### 4.2 Register the iPhone with Apple

The operator receives the new device identifier through the Firebase alert or
exports it privately from **App Distribution > Testers & Groups > All testers
> Export Apple UDIDs**. In Apple **Certificates, Identifiers & Profiles >
Devices**, register the intended iPhone by its device name and identifier.

Before registration:

- verify the tester and device through a private channel;
- check the Apple annual device allowance and existing entries;
- avoid duplicate or stale device names; and
- never paste the identifier into Git, release notes, a public chat, or an
  issue tracker.

Apple currently allows a limited number of registered devices per product
family in each membership year. Disabling a device during the year does not
restore its slot.

### 4.3 Refresh the Ad Hoc profile

In Apple **Profiles**, select the manual Ad Hoc profile for the self-hosted App
ID, choose **Edit**, retain the intended distribution certificate, include the
new device plus every still-authorized device, generate the profile, and
download it to a private path outside Git.

Update these local inputs:

```sh
export ENTE_IOS_ADHOC_PROFILE="/absolute/private/path/refreshed.mobileprovision"
export ENTE_IOS_EXPECTED_DEVICE_COUNT="the-exact-positive-count"
export ENTE_IOS_BUILD_NUMBER="a-higher-positive-build-number"
```

Firebase documents that a device-only profile refresh can reuse the same app
version and build number. This repository's guarded ledger intentionally uses
a stricter rule: every later publication must increase `CFBundleVersion`.
Follow the local rule so the release remains unambiguous and installable as an
update.

Prepare, preflight, and publish the refreshed build through section 3. Never
manually re-sign or upload the earlier IPA: its embedded profile does not
contain the new device.

### 4.4 Install the application

After Firebase notifies the tester that the refreshed build is available:

1. Open the App Distribution web clip using the Google account that accepted
   the invitation.
2. Select **Ente Photos Self-Hosted**, review the release notes and source link,
   and tap **Download**.
3. If iOS reports **Developer Mode Required**, open **Settings > Privacy &
   Security > Developer Mode**, enable it, restart the iPhone, unlock it, and
   confirm **Turn On** with the device passcode.
4. Launch the installed application.

Developer Mode is required to launch Ad Hoc applications on iOS 16 or later.
It does not replace Firebase acceptance, Apple device registration, or device
inclusion in the profile. This application intentionally has no Firebase App
Distribution SDK; later builds arrive by email and through the web clip, not
an in-application update prompt.

### 4.5 Grant the minimum Tailscale access

Choose the method that matches the existing tailnet design; this runbook does
not change access-control policy automatically:

- **Share the Museum host** when the tester needs only the fixed host that
  serves Museum and object storage. The tester remains in their own tailnet and
  uses the server's full `*.ts.net` name. Confirm both tailnets' access controls
  allow the required HTTPS ports.
- **Invite the tester as a Member** when the deployment requires subnet-router
  access or multiple tailnet resources. Restrict the Member through the
  existing access policy and approve the user if user approval is enabled.

Do not enable Tailscale Funnel or expose the Photos/Albums web applications for
this mobile beta. Share or invite through the Tailscale admin console, then
privately coordinate acceptance. Unused Tailscale user invitations currently
expire after 30 days.

On the iPhone, the tester installs the official Tailscale client, signs in with
their own identity, permits the VPN configuration, accepts the intended invite
or machine share, and connects Tailscale. Before opening Ente Photos, verify the
device can open this URL and receive `pong`:

```text
https://museum-host.tailnet-name.ts.net/ping
```

If Museum is reachable but uploads fail, verify the separate signed
object-storage hostname and port from that same iPhone.

### 4.6 Sign in and prove encrypted media flow

The tester uses their own Museum account, not the Firebase, Apple, or Tailscale
credentials. The compiled server should already be the intended private
origin. If it must be changed, use the application's Server Settings flow;
changing a server while signed in requires completing local logout first.

For the controlled acceptance test:

1. Confirm the application shows the intended private server and release
   version.
2. Sign in to the tester's individual Museum account.
3. Upload one non-sensitive test photo while the application is in the
   foreground.
4. Wait until the item reports as backed up or synchronized.
5. Download or export the cloud item and confirm it is readable in Apple
   Photos.
6. Force-quit and reopen the application; confirm the account, server binding,
   cloud library, and readable media remain available.
7. Report success privately. Do not commit account details, device identifiers,
   screenshots containing identities, or media.

## 5. First installation and later updates

### Bundle-identifier cutover for the owner

The legacy bundle `com.vanton1.ente.photos.selfhosted` and the Firebase bundle
`me.vanton.ente.photos.selfhosted` are unrelated iOS applications. Local
preferences, databases, keychain state, cached keys, server binding, and
sessions do not migrate.

Keep both installed while proving the Firebase application. Before deleting
the legacy application:

1. Confirm all intended media is backed up to Museum and can be downloaded.
2. Confirm the Firebase-installed application passed section 4.6 and survived a
   force-quit/restart.
3. Confirm the account password, second-factor method, and recovery material
   are available outside the iPhone.
4. Accept that deleting the legacy application discards its app-local state.

Then remove only the legacy bundle. Encrypted cloud media remains associated
with the Museum account rather than the iOS bundle identifier.

### In-place Firebase updates

Every update must keep all of these stable:

- bundle `me.vanton.ente.photos.selfhosted`;
- Apple organization team and App ID;
- the reviewed signing/profile policy and currently authorized device set; and
- the intended private-server policy.

The `CFBundleVersion` must increase. Prepare and publish through section 3;
never upload a manually rebuilt IPA. The tester opens the new Firebase build
and installs it over the existing application without deleting it. Afterward,
verify the account, server binding, cloud library, and media remain intact,
then repeat one controlled upload/download and force-restart test.

## 6. Remove a tester

Offboarding is complete only after delivery, future device authorization,
network access, and server access are handled.

1. In Firebase **Testers & Groups**, remove the person from
   `trusted-ios-testers`. Check for access through another group or individual
   release assignment.
2. If the person no longer needs any project release, remove the tester from
   the Firebase project as well.
3. Exclude their iPhone from the next Ad Hoc provisioning profile. Disable the
   Apple device only when appropriate for the organization's device policy;
   disabling it during the membership year does not recover the device slot.
4. Revoke the Tailscale machine share or remove/suspend the tailnet Member and
   their devices according to the existing tailnet policy.
5. Disable or remove the person's Museum account according to the server's
   account-retention policy. Do not delete encrypted server data without a
   separate explicit decision.
6. Record completion only in the private administrative system, not this
   repository.

CLI equivalents for the Firebase steps are:

```sh
"$FIREBASE_CLI" appdistribution:testers:remove "<tester-email>" \
  --group-alias trusted-ios-testers \
  --project "$ENTE_FIREBASE_PROJECT_ID"

"$FIREBASE_CLI" appdistribution:testers:remove "<tester-email>" \
  --project "$ENTE_FIREBASE_PROJECT_ID"
```

An already installed IPA can continue running while its signing authorization
remains valid. Firebase and a refreshed future profile are delivery controls,
not remote kill switches; private-server access must be revoked separately.

## 7. Recovery procedures

| Problem | Required response |
|---|---|
| Prepared IPA or manifest changed | Stop. Discard the pair and prepare again from clean pushed source. Do not make it writable or repair it. |
| Wrong Firebase app, bundle, or group | Stop before confirmation. Correct the local inputs or registration; never upload to see whether Firebase accepts it. |
| Firebase failure after upload started | Preserve the partial-attempt receipt, inspect the console, and reconcile whether the release and group distribution exist before retrying. |
| Invitation expired or was accepted with the wrong Google account | Remove stale tester access if necessary, resend the invitation, and privately confirm the intended Google identity before device registration. |
| Tester sees “device registered” but cannot download | Add the collected device to Apple, refresh the Ad Hoc profile, increase the build number, prepare, and publish the new IPA. |
| “Unable to Install” or integrity/profile error | Confirm the exact iPhone is enabled in Apple and embedded in the IPA's unexpired profile; then rebuild through the guarded path. Do not manually re-sign the IPA. |
| “Developer Mode Required” | Enable Developer Mode under iOS Privacy & Security, restart, unlock, and confirm with the device passcode. |
| Firebase release expired | Prepare the known-good source with a higher build number and publish it through the guarded path. Do not bypass the receipt ledger by reusing the old build number. |
| Bad application release | Select the last known-good public commit, increase its build number, prepare and publish it as a forward rollback, then repeat device acceptance. |
| Provisioning profile expired or is near expiry | Regenerate the same Ad Hoc profile with the intended certificate/devices, increase the build number, and publish a fresh guarded build before acceptance testing. |
| Distribution certificate private key is lost | Stop publishing with the missing identity. While authorized Apple organization access remains, issue a replacement distribution certificate, generate a new profile, update the reviewed certificate pin in source, and publish a higher-build recovery release. |
| Distribution certificate is compromised | Revoke it through Apple, which invalidates profiles containing it; issue a replacement, regenerate the profile, update the reviewed pin, and distribute a higher-build replacement. Review Apple and Firebase access separately. |
| Apple membership, agreement, or team access lapses | Restore the organization membership/agreement/authorized role before generating certificates or profiles. Firebase access alone cannot repair Apple authorization. |
| Museum or object storage is unavailable | Restore containers, proxy, Tailscale, DNS, and object-storage health. Do not publish an unchanged application for a server outage. |
| Tester cannot reach the private host | Check Tailscale VPN state, accepted share/membership, approval state, full `*.ts.net` name, and access rules before changing the application. |
| Tester chose the wrong server | Complete local logout, select and validate the correct server through Server Settings, then sign in to the correct Museum account. |
| Firebase operator account is compromised | Revoke the Firebase CLI session, rotate affected credentials, review project membership/releases/testers, and reauthenticate. Do not print login JSON while investigating. |

The current local signing policy does not export the distribution private key
for off-machine backup. Unlike an Android package-key loss, an authorized Apple
organization can recover by issuing a new Apple Distribution certificate under
the same team and App ID. That recovery still requires a new profile, a
reviewed source change to the certificate pin, a higher build number, and full
acceptance testing.

If a valid Ad Hoc application fails only on a highly restricted network, also
check whether Apple's provisioning-profile quality service is reachable. Some
Apple teams require development- and Ad-Hoc-signed applications to contact
`https://ppq.apple.com` when first launched.

## 8. Retention and primary references

These external rules were verified on 2026-07-18 and can change:

- Firebase tester invitations expire after 30 days if unaccepted; the console
  warns shortly before expiry and can resend them.
- Firebase App Distribution releases are retained for 150 days and are also
  subject to a 1,000-release-per-app limit. Installed copies continue running
  after a release disappears from Firebase, subject to Apple signing and
  profile validity.
- For an Ad Hoc release, Firebase collects the tester iPhone identifier through
  its configuration profile; Apple registration and a rebuilt IPA containing
  that device are still required.
- An Apple Developer Program team can register only a limited number of devices
  per product family in each membership year. Disabling a device during the
  year does not restore a slot.
- Ad Hoc applications on iOS 16 or later require Developer Mode to launch.
- Unused Tailscale user invitations expire after 30 days. A machine share is
  suitable for a fixed host; full tailnet membership is needed for broader
  resources such as subnet-router access.

Primary references:

- [Firebase iOS CLI distribution](https://firebase.google.com/docs/app-distribution/ios/distribute-cli)
- [Firebase tester setup on iOS](https://firebase.google.com/docs/app-distribution/get-set-up-as-a-tester)
- [Firebase registration of additional iOS devices](https://firebase.google.com/docs/app-distribution/register-additional-devices)
- [Firebase tester and group management](https://firebase.google.com/docs/app-distribution/add-remove-testers)
- [Firebase App Distribution retention and troubleshooting](https://firebase.google.com/docs/app-distribution/troubleshooting)
- [Apple: register a single device](https://developer.apple.com/help/account/devices/register-a-single-device)
- [Apple: device limits and membership-year behavior](https://developer.apple.com/help/account/devices/devices-overview/)
- [Apple: create an Ad Hoc provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/)
- [Apple: edit, download, or regenerate provisioning profiles](https://developer.apple.com/help/account/provisioning-profiles/edit-download-or-delete-profiles/)
- [Apple: enable Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [Apple: provisioning-profile updates and first-launch checks](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates/)
- [Tailscale: inviting users versus sharing a device](https://tailscale.com/docs/reference/inviting-vs-sharing)
- [Tailscale machine sharing](https://tailscale.com/docs/features/sharing)
- [Tailscale user invitations](https://tailscale.com/docs/features/sharing/how-to/invite-any-user)
- [Tailscale on iOS](https://tailscale.com/docs/install/ios)
- [Ente object-storage reachability](../../../docs/docs/self-hosting/administration/object-storage.md)
