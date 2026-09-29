# XLSMART Enterprise: upstream release procedure

This fork keeps Onyx internal module names, database schemas, and service names. It changes user-facing identity only. Keep the original root `LICENSE` and notices. The `ee` directories use a separate Onyx Enterprise License; obtain the required agreement before using paid EE features in production.

## Branches and first publication

- `upstream-tracking` points at the latest stable Onyx release fetched into `refs/tags/upstream/vX.Y.Z`. Never add a local commit to this branch.
- `xlsmart-main` contains the upstream history and XLSMART branding commits. Set this as the fork's default branch.
- `sync/vX.Y.Z` is a temporary merge branch. Merge it through a reviewed PR only.

The fork is [xlsmartenterprise/onyx-enterprise](https://github.com/xlsmartenterprise/onyx-enterprise), with `xlsmart-main` as its default branch and `upstream-tracking` published. `origin` points to the fork; `upstream` remains `https://github.com/onyx-dot-app/onyx.git`. Do not enable Git `rerere` globally; if needed, set it only in this checkout.

Before enabling the weekly workflow, add `SYNC_GITHUB_TOKEN` as an Actions secret **from a dedicated fine-grained token or GitHub App installation token** scoped only to this fork. Grant Contents: read/write, Pull requests: read/write and Workflows: read/write; the workflow needs the last permission to push `.github/workflows/**`. Do **not** reuse the operator's broad GitHub OAuth credential as a CI secret. Restrict workflow starts, branch pushes and merges to `xlsmart-main`. Run a manual sync and inspect the resulting PR/CI before trusting the schedule. A live PR dry-run remains blocked until a suitably scoped automation token is provided.

## Weekly release update

`.github/workflows/upstream-sync.yml` fetches upstream `v*` tags into the separate `refs/tags/upstream/v*` namespace each Monday at 02:00 UTC. It selects the highest stable upstream `vX.Y.Z` tag. Fork-owned `vX.Y.Z` tags cannot select a release or move the pristine mirror. The job fast-forwards `upstream-tracking` to that upstream tag and checks whether `xlsmart-main` already contains it. If not, it merges the namespaced tag into `sync/vX.Y.Z`, reapplies branded assets, pushes that branch, and opens a PR. An existing open PR is left unchanged. If a same-name branch exists without an open PR, the job fails so an operator can inspect it. No production deployment happens from this workflow.

Do not substitute `upstream/main` for a stable release tag. At this baseline, `v4.8.1` is not an ancestor of upstream `main`. A direct merge from `main` needs separate conflict review.

Before merging the PR:

1. Review the upstream changelog, dependency changes, migrations, licensing, and files that overlap the branding overlay.
2. Confirm the root `LICENSE` and each `ee` license remain intact. Do not turn on paid EE features without the required agreement.
3. Run the relevant frontend build and backend checks on the PR. Deploy the PR to staging and check login, app title and favicon, light and dark logos, email branding, widget and Chrome extension assets.
4. Exercise a connector sync and a search query against the staging deployment. Confirm both work with the existing database and internal service names.
5. Merge to `xlsmart-main` only after CI and staging smoke checks pass. Deploy from that branch; delete the temporary branch after merge.

## Scheduled maintenance on the fork

The three weekly workflows `update-base-image-digests.yml`, `update-vendored-skills.yml`, and `update-recommended-models.yml` check out the repository's actual default branch (`xlsmart-main` here, `main` upstream). Configure **both** the `CHERRY_PICK_APP_ID` repository variable and `CHERRY_PICK_APP_PRIVATE_KEY` secret to use a dedicated GitHub App; with no App ID they use the built-in `GITHUB_TOKEN`. Contents and Pull requests write permissions are scoped to the three updater **jobs**, while their notification jobs and the fork's default workflow token stay read-only. Creating updater PRs without an App requires the repository Actions setting **Allow GitHub Actions to create and approve pull requests**; this applies repository-wide, so review permissions and never configure automatic approval or merge. Never copy a personal OAuth token into Actions secrets.

The digest updater requires `DOCKER_USERNAME` and `DOCKER_TOKEN` with **private `dhi.io` catalog access** in addition to public Docker Hub access; the fork currently has neither secret. Until both are configured, the workflow succeeds with an explicit notice and **does not refresh any digest or create a digest PR**. It never publishes only public pins while their hardened counterparts are inaccessible. If a family edits `.github/workflows/**` (currently `node`), it is also skipped when using `GITHUB_TOKEN`: configure a dedicated App with Workflows: write (plus Contents and Pull requests: write) to update that family. Do not interpret the green credential-check run as a digest update.

On 29 September 2026, manual dispatches of all three workflows completed successfully on `xlsmart-main`: vendored skills had no upstream changes; the model updater opened [review PR #1](https://github.com/xlsmartenterprise/onyx-enterprise/pull/1) against `xlsmart-main`; the digest updater reported the missing Docker catalog credentials. GitHub does not start ordinary PR/push CI from events emitted by `GITHUB_TOKEN`; PR #1 had no automatic checks. Manually run relevant checks on its branch and review the generated JSON before merging, or provision the dedicated App to restore normal event-triggered CI. This does **not** supply the separate `SYNC_GITHUB_TOKEN` needed by the upstream release-sync workflow.

## Conflict or workflow failure

A merge conflict stops the workflow before any sync branch is pushed. Inspect the failed job's conflicted file list. From an up-to-date local checkout, fetch both remotes and use a new branch at `origin/xlsmart-main`:

```bash
git fetch origin xlsmart-main
git fetch --no-tags --prune upstream '+refs/tags/v*:refs/tags/upstream/v*'
git switch -c sync/vX.Y.Z origin/xlsmart-main
git merge --no-ff refs/tags/upstream/vX.Y.Z
```

Resolve the conflict. Keep the XLSMART overlay in display code and assets, but preserve upstream internal identifiers. Stage the resolved files and commit the merge. Install Python 3 and Pillow 12.3.0 in a workspace-local environment, then run `bash scripts/apply_xlsmart_assets.sh` and commit any resulting asset changes. Run the checks above, push the branch, and open a PR to `xlsmart-main`. If the sync branch already exists, inspect its commits and PR before updating it. Never force-push without team review. If a job fails while creating a PR, inspect the pushed branch and the token permissions before rerunning it.

## Urgent upstream security fixes

For a confirmed upstream fix, start a `hotfix/<advisory>` branch at `xlsmart-main`. Record the upstream commit SHA and advisory. Cherry-pick only the applicable fix. Resolve conflicts without renaming internal modules. Run focused tests and a staging smoke check. Open an audited PR and deploy after approval. When a later upstream release contains the commit, review the normal merge for duplicate changes rather than cherry-picking it again.

## Rebranding overlay

Set `APPLICATION_NAME=XLSMART Enterprise` for the backend.
Set `NEXT_PUBLIC_APP_NAME=XLSMART Enterprise` when building the web image.
The web build embeds `NEXT_PUBLIC_*` values in client bundles.
An explicit enterprise `application_name` overrides these defaults.
Rebuild and deploy the web image after changing its public name.

Set `ONYX_BACKEND_IMAGE` and `ONYX_WEB_SERVER_IMAGE` to branded tags when deploying prebuilt images.
Keep the existing Compose service names.
The asset script restores checked-in XLSMART marks after upstream merges.
Review upstream changes to asset paths before using the script.
Do not rename Python imports, database tables, internal Docker services, or API routes to change the product name.

Keep the upstream "Powered by Onyx" attribution unless Onyx explicitly permits its removal.
The existing Compose template requires permission before you enable its attribution toggle.

The Chrome extension defaults to `http://localhost:3000` for development. Set the XLSMART deployment URL on its welcome or options page before using it in production. Keep existing extension storage keys so installed users retain their settings.
