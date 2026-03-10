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
