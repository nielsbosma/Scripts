const vscode = require('vscode');
const path = require('path');
const fs = require('fs');

async function saveIfOpen(uri) {
    if (!uri) return;
    const doc = vscode.workspace.textDocuments.find(
        d => d.uri.toString() === uri.toString()
    );
    if (doc && doc.isDirty) {
        await doc.save();
    }
}

function activate(context) {
    // Update Plan - runs UpdatePlan.ps1 on the selected .md file
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.updatePlan', async (uri) => {
            if (!uri) return;
            await saveIfOpen(uri);
            const terminal = vscode.window.createTerminal('Update Plan');
            terminal.show();
            terminal.sendText(`& "D:\\Repos\\_Personal\\Scripts\\UpdatePlan.ps1" "${uri.fsPath}" -ReadyToGo`);
        })
    );

    // Approve Plan - moves .md file to approved/ subdirectory
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.approvePlan', async (uri) => {
            if (!uri) return;
            await saveIfOpen(uri);
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
            if (!uri) return;
            await saveIfOpen(uri);
            const terminal = vscode.window.createTerminal('Split Plan');
            terminal.show();
            terminal.sendText(`& "D:\\Repos\\_Personal\\Scripts\\SplitPlan.ps1" "${uri.fsPath}" -ReadyToGo`);
        })
    );

    // Make Plan - runs MakePlan.ps1 (command palette only, no file context)
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.makePlan', () => {
            const terminal = vscode.window.createTerminal('Make Plan');
            terminal.show();
            terminal.sendText(`& "D:\\Repos\\_Personal\\Scripts\\MakePlan.ps1"`);
        })
    );
}

function deactivate() {}

module.exports = { activate, deactivate };
