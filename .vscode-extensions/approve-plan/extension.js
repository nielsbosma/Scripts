const vscode = require('vscode');
const path = require('path');
const fs = require('fs');

function activate(context) {
    const disposable = vscode.commands.registerCommand('ivy.approvePlan', async (uri) => {
        if (!uri) return;

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
    });

    context.subscriptions.push(disposable);
}

function deactivate() {}

module.exports = { activate, deactivate };
