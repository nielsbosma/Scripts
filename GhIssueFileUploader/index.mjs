#!/usr/bin/env node

import { chromium } from "playwright";
import { resolve, join } from "path";
import { existsSync } from "fs";
import { homedir } from "os";

const args = process.argv.slice(2);

if (args.length < 2) {
  console.error(
    "Usage: node index.mjs <github-issue-url> <file1> [file2] [...]"
  );
  process.exit(1);
}

const issueUrl = args[0];
const filePaths = args.slice(1).map((f) => resolve(f));

// Validate URL
if (!/^https:\/\/github\.com\/.+\/(issues|pull)\/\d+/.test(issueUrl)) {
  console.error(
    "Error: URL must be a GitHub issue or PR URL (https://github.com/<owner>/<repo>/issues|pull/<number>)"
  );
  process.exit(1);
}

// Validate files exist
for (const f of filePaths) {
  if (!existsSync(f)) {
    console.error(`Error: File not found: ${f}`);
    process.exit(1);
  }
}

const stateDir = join(homedir(), ".gh-issue-uploader");
const statePath = join(stateDir, "auth.json");

console.log(`Opening issue: ${issueUrl}`);
console.log(`Uploading ${filePaths.length} file(s)...`);

// Use a persistent browser context so login state is preserved across runs
const { mkdirSync } = await import("fs");
mkdirSync(stateDir, { recursive: true });

let context;
let browser;
try {
  // Use persistent context for automatic cookie/session storage
  context = await chromium.launchPersistentContext(stateDir, {
    headless: false,
    args: ["--disable-blink-features=AutomationControlled"],
  });

  const page = context.pages()[0] || (await context.newPage());

  // Check if we're logged in by navigating to the issue
  await page.goto(issueUrl, { waitUntil: "domcontentloaded" });

  // Check for comment box (means we're logged in)
  const commentBox = page.locator("textarea#new_comment_field");
  let loggedIn = false;
  try {
    await commentBox.waitFor({ state: "visible", timeout: 5000 });
    loggedIn = true;
  } catch {
    // Not logged in
  }

  if (!loggedIn) {
    console.log(
      "Not logged in to GitHub. Please log in in the browser window..."
    );
    console.log(
      "After logging in, navigate to the issue/PR URL or just wait — the script will detect your login."
    );

    // Navigate to login page
    await page.goto("https://github.com/login", {
      waitUntil: "domcontentloaded",
    });

    // Poll until the user is logged in: check for the avatar/profile menu on any GitHub page
    // This handles 2FA, device verification, and any other intermediate steps
    const maxWait = 300000; // 5 minutes
    const start = Date.now();
    while (Date.now() - start < maxWait) {
      await new Promise((r) => setTimeout(r, 2000));
      try {
        // Try navigating to the issue to check if login succeeded
        const currentUrl = page.url();
        if (
          !currentUrl.includes("/login") &&
          !currentUrl.includes("/sessions") &&
          !currentUrl.includes("/two-factor")
        ) {
          // Might be logged in, navigate to issue and verify
          await page.goto(issueUrl, { waitUntil: "domcontentloaded" });
          try {
            await commentBox.waitFor({ state: "visible", timeout: 5000 });
            loggedIn = true;
            break;
          } catch {
            // Not yet, go back to let user continue
            await page.goBack();
          }
        }
      } catch {
        // Ignore navigation errors during login flow
      }
    }

    if (!loggedIn) {
      console.error("Error: Login timed out after 5 minutes.");
      process.exit(1);
    }

    console.log("Login successful!");
  }

  // Focus the comment box
  await commentBox.click();

  // Find the file input in the comment form
  const fileInput = page
    .locator('file-attachment input[type="file"]')
    .last();

  // Upload all files at once
  await fileInput.setInputFiles(filePaths);

  // Wait for uploads to complete - GitHub inserts markdown links into the textarea
  console.log("Waiting for upload(s) to complete...");
  await page.waitForFunction(
    ({ count }) => {
      const textarea = document.querySelector("#new_comment_field");
      if (!textarea) return false;
      const value = textarea.value;
      // GitHub inserts ![...](url) for images or [filename](url) for other files
      const linkMatches = value.match(/!?\[.*?\]\(https:\/\/.*?\)/g);
      return linkMatches && linkMatches.length >= count;
    },
    { count: filePaths.length },
    { timeout: 60000 }
  );

  console.log("Upload(s) complete. Submitting comment...");

  // Click the submit button
  const submitButton = page
    .locator('button[type="submit"].btn-primary:has-text("Comment")')
    .last();
  await submitButton.click();

  // Wait for comment to appear
  await page.waitForTimeout(3000);

  console.log("Done! Comment posted successfully.");
} catch (err) {
  console.error(`Error: ${err.message}`);
  process.exit(1);
} finally {
  if (context) {
    await context.close();
  }
}
