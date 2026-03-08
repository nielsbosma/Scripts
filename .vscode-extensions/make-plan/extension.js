const vscode = require('vscode');

function activate(context) {
    const disposable = vscode.commands.registerCommand('ivy.makePlan', () => {
        const terminal = vscode.window.createTerminal('Make Plan');
        terminal.show();
        terminal.sendText(`& "D:\\Repos\\_Personal\\Scripts\\MakePlan.ps1"`);
    });

    context.subscriptions.push(disposable);
}

function deactivate() {}

module.exports = { activate, deactivate };
