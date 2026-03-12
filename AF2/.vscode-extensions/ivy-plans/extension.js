const vscode = require('vscode');
const path = require('path');
const fs = require('fs');

async function saveAndClose(uri) {
    if (!uri) return;
    const doc = vscode.workspace.textDocuments.find(
        d => d.uri.toString() === uri.toString()
    );
    if (doc) {
        if (doc.isDirty) {
            await doc.save();
        }
        // Find the tab and close it
        for (const group of vscode.window.tabGroups.all) {
            for (const tab of group.tabs) {
                if (tab.input instanceof vscode.TabInputText &&
                    tab.input.uri.toString() === uri.toString()) {
                    await vscode.window.tabGroups.close(tab);
                    return;
                }
            }
        }
    }
}

async function openNextPlan(plansDir, excludeFile) {
    const files = fs.readdirSync(plansDir)
        .filter(f => f.endsWith('.md') && f !== excludeFile)
        .sort();
    if (files.length > 0) {
        const nextUri = vscode.Uri.file(path.join(plansDir, files[0]));
        await vscode.window.showTextDocument(nextUri);
    } else {
        vscode.window.showInformationMessage('No more plans in queue');
    }
}

function activate(context) {
    // Update Plan - runs UpdatePlan.ps1 on the selected .md file
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.updatePlan', async (uri) => {
            if (!uri && vscode.window.activeTextEditor) {
                uri = vscode.window.activeTextEditor.document.uri;
            }
            if (!uri) return;
            await saveAndClose(uri);
            const terminal = vscode.window.createTerminal({ name: 'Update Plan', shellPath: 'pwsh' });
            terminal.show();
            terminal.sendText(`& "D:\\Repos\\_Personal\\Scripts\\AF2\\UpdatePlan.ps1" "${uri.fsPath}"`);
            await openNextPlan(path.dirname(uri.fsPath), path.basename(uri.fsPath));
        })
    );

    // Approve Plan - moves .md file to approved/ subdirectory
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.approvePlan', async (uri) => {
            if (!uri && vscode.window.activeTextEditor) {
                uri = vscode.window.activeTextEditor.document.uri;
            }
            if (!uri) return;
            await saveAndClose(uri);
            const filePath = uri.fsPath;
            const dir = path.dirname(filePath);
            const fileName = path.basename(filePath);
            const approvedDir = path.join(dir, 'approved');

            if (!fs.existsSync(approvedDir)) {
                fs.mkdirSync(approvedDir, { recursive: true });
            }

            const dest = path.join(approvedDir, fileName);
            if (fs.existsSync(dest)) {
                const overwrite = await vscode.window.showWarningMessage(
                    `"${fileName}" already exists in approved/. Overwrite?`,
                    'Yes', 'No'
                );
                if (overwrite !== 'Yes') return;
            }

            fs.renameSync(filePath, dest);
            vscode.window.showInformationMessage(`Approved: ${fileName}`);
            await openNextPlan(dir, fileName);
        })
    );

    // Split Plan - runs SplitPlan.ps1 on the selected .md file
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.splitPlan', async (uri) => {
            if (!uri && vscode.window.activeTextEditor) {
                uri = vscode.window.activeTextEditor.document.uri;
            }
            if (!uri) return;
            await saveAndClose(uri);
            const terminal = vscode.window.createTerminal({ name: 'Split Plan', shellPath: 'pwsh' });
            terminal.show();
            terminal.sendText(`& "D:\\Repos\\_Personal\\Scripts\\AF2\\SplitPlan.ps1" "${uri.fsPath}"`);
            await openNextPlan(path.dirname(uri.fsPath), path.basename(uri.fsPath));
        })
    );

    // Skip Plan - moves .md file to skipped/ subdirectory
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.skipPlan', async (uri) => {
            if (!uri && vscode.window.activeTextEditor) {
                uri = vscode.window.activeTextEditor.document.uri;
            }
            if (!uri) return;
            await saveAndClose(uri);
            const filePath = uri.fsPath;
            const dir = path.dirname(filePath);
            const fileName = path.basename(filePath);
            const skippedDir = path.join(dir, 'skipped');

            if (!fs.existsSync(skippedDir)) {
                fs.mkdirSync(skippedDir, { recursive: true });
            }

            const dest = path.join(skippedDir, fileName);
            if (fs.existsSync(dest)) {
                const overwrite = await vscode.window.showWarningMessage(
                    `"${fileName}" already exists in skipped/. Overwrite?`,
                    'Yes', 'No'
                );
                if (overwrite !== 'Yes') return;
            }

            fs.renameSync(filePath, dest);
            vscode.window.showInformationMessage(`Skipped: ${fileName}`);
            await openNextPlan(dir, fileName);
        })
    );

    // Create Ivy-Framework Issue - prepends issue header and moves to approved/
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.createIvyFrameworkIssue', async (uri) => {
            if (!uri && vscode.window.activeTextEditor) {
                uri = vscode.window.activeTextEditor.document.uri;
            }
            if (!uri) return;
            await saveAndClose(uri);
            const filePath = uri.fsPath;
            const fileName = path.basename(filePath);

            // Prepend issue header
            const content = fs.readFileSync(filePath, 'utf8');
            const header = '> DO NOT IMPLEMENT - ADD AS A GITHUB ISSUE IN IVY-FRAMEWORK REPO\n> Add label "api-review-required"\n\n';
            fs.writeFileSync(filePath, header + content, 'utf8');

            // Move to approved
            const approvedDir = path.join(path.dirname(filePath), 'approved');
            if (!fs.existsSync(approvedDir)) {
                fs.mkdirSync(approvedDir, { recursive: true });
            }
            const dest = path.join(approvedDir, fileName);
            if (fs.existsSync(dest)) {
                const overwrite = await vscode.window.showWarningMessage(
                    `"${fileName}" already exists in approved/. Overwrite?`,
                    'Yes', 'No'
                );
                if (overwrite !== 'Yes') return;
            }
            fs.renameSync(filePath, dest);
            vscode.window.showInformationMessage(`Created Ivy-Framework issue: ${fileName}`);
        })
    );

    // Make Plan - runs MakePlan.ps1 (opens Notepad for input)
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.makePlan', () => {
            const terminal = vscode.window.createTerminal({ name: 'Make Plan', shellPath: 'pwsh' });
            terminal.show();
            terminal.sendText(`& "D:\\Repos\\_Personal\\Scripts\\AF2\\MakePlan.ps1"`);
        })
    );
}

function deactivate() {}

module.exports = { activate, deactivate };
