"use strict";

const MARKER = "<!-- ente-upstream-sync -->";
const TITLE = "Official Ente changes are ready to synchronize";

function validateReport(report) {
    if (report?.schemaVersion !== 1 || report?.ready !== true) {
        throw new Error("The local drift checker did not produce a ready schema-v1 report.");
    }

    const commits = report.commits;
    const sha = /^[0-9a-f]{40}$/;
    if (
        !commits ||
        !sha.test(commits.fork || "") ||
        !sha.test(commits.official || "") ||
        !sha.test(commits.mergeBase || "") ||
        !Number.isInteger(commits.forkOnly) ||
        commits.forkOnly < 0 ||
        !Number.isInteger(commits.upstreamOnly) ||
        commits.upstreamOnly < 0
    ) {
        throw new Error("The drift report contains invalid commit evidence.");
    }
    return commits;
}

function issueBody(commits, checkedAt) {
    return [
        MARKER,
        "",
        "The scheduled fork check found official Ente commits that are not yet in this fork.",
        "",
        `- Fork main: \`${commits.fork}\``,
        `- Official main: \`${commits.official}\``,
        `- Merge base: \`${commits.mergeBase}\``,
        `- Fork-only commits: ${commits.forkOnly}`,
        `- Upstream-only commits: ${commits.upstreamOnly}`,
        `- Last checked: ${checkedAt}`,
        "",
        "Run the guarded synchronizer from a clean local `main`:",
        "",
        `\`./scripts/sync_upstream.sh run --official-sha ${commits.official}\``,
        "",
        "The local command preserves conflicts, validates the mobile workspace, requires typed confirmation before pushing, and opens a pull request without merging it.",
    ].join("\n");
}

async function openMarkerIssues(github, repo) {
    const issues = await github.paginate(github.rest.issues.listForRepo, {
        ...repo,
        state: "open",
        per_page: 100,
    });
    return issues.filter(
        (issue) => !issue.pull_request && (issue.body || "").includes(MARKER),
    );
}

async function reconcile({ github, context, report, now = new Date() }) {
    const commits = validateReport(report);
    const existing = await openMarkerIssues(github, context.repo);
    if (existing.length > 1) {
        throw new Error(`Found ${existing.length} open issues with the upstream-sync marker; refusing an ambiguous update.`);
    }

    const issue = existing[0];
    if (commits.upstreamOnly > 0) {
        const body = issueBody(commits, now.toISOString());
        if (issue) {
            const response = await github.rest.issues.update({
                ...context.repo,
                issue_number: issue.number,
                title: TITLE,
                body,
            });
            return { action: "updated", number: response.data.number, url: response.data.html_url };
        }

        const response = await github.rest.issues.create({
            ...context.repo,
            title: TITLE,
            body,
        });
        return { action: "created", number: response.data.number, url: response.data.html_url };
    }

    if (!issue) return { action: "unchanged", number: null, url: null };

    await github.rest.issues.createComment({
        ...context.repo,
        issue_number: issue.number,
        body: `Fork main now contains official Ente through \`${commits.official}\`. Closing the drift report.`,
    });
    const response = await github.rest.issues.update({
        ...context.repo,
        issue_number: issue.number,
        state: "closed",
        state_reason: "completed",
    });
    return { action: "closed", number: response.data.number, url: response.data.html_url };
}

module.exports = { MARKER, TITLE, issueBody, reconcile, validateReport };
