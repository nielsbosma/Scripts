const vscode = require('vscode');

function activate(context) {
    const disposable = vscode.commands.registerCommand('ivy.updatePlan', (uri) => {
        if (!uri) return;

        const filePath = uri.fsPath;
        const terminal = vscode.window.createTerminal('Update Plan');
        terminal.show();
        terminal.sendText(`& "D:\\Repos\\_Personal\\Scripts\\UpdatePlan.ps1" "${filePath}" -ReadyToGo`);
    });

    context.subscriptions.push(disposable);
}

function deactivate() {}

module.exports = { activate, deactivate };
