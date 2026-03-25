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

    // Expand Plan - runs ExpandPlan.ps1 on the selected .md file
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.expandPlan', async (uri) => {
            if (!uri && vscode.window.activeTextEditor) {
                uri = vscode.window.activeTextEditor.document.uri;
            }
            if (!uri) return;
            await saveAndClose(uri);
            const terminal = vscode.window.createTerminal({ name: 'Expand Plan', shellPath: 'pwsh' });
            terminal.show();
            terminal.sendText(`& "D:\\Repos\\_Personal\\Scripts\\AF2\\ExpandPlan.ps1" "${uri.fsPath}"`);
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

    // Create Ivy-Mcp Issue - prepends issue header and moves to approved/
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.createIvyMcpIssue', async (uri) => {
            if (!uri && vscode.window.activeTextEditor) {
                uri = vscode.window.activeTextEditor.document.uri;
            }
            if (!uri) return;
            await saveAndClose(uri);
            const filePath = uri.fsPath;
            const fileName = path.basename(filePath);

            // Prepend issue header
            const content = fs.readFileSync(filePath, 'utf8');
            const header = '> DO NOT IMPLEMENT - ADD AS A GITHUB ISSUE IN IVY-MCP REPO\n\n';
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
            vscode.window.showInformationMessage(`Created Ivy-Mcp issue: ${fileName}`);
        })
    );

    // Test Plan - runs IvyFeatureTester.ps1 on the selected .md file
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.testPlan', async (uri) => {
            if (!uri && vscode.window.activeTextEditor) {
                uri = vscode.window.activeTextEditor.document.uri;
            }
            if (!uri) return;
            await saveAndClose(uri);
            const terminal = vscode.window.createTerminal({ name: 'Ivy Test', shellPath: 'pwsh' });
            terminal.show();
            terminal.sendText(`& "D:\\Repos\\_Personal\\Scripts\\AF2\\IvyFeatureTester.ps1" "${uri.fsPath}"`);
        })
    );

    // Follow-Up Plan - like Make Plan but prepends [number] from the source file
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.followUpPlan', async (uri) => {
            try {
                if (!uri && vscode.window.activeTextEditor) {
                    uri = vscode.window.activeTextEditor.document.uri;
                }
                if (!uri) return;

                const fileName = path.basename(uri.fsPath);
                const match = fileName.match(/^(\d+)[-_]/);
                if (!match) {
                    vscode.window.showWarningMessage('File does not start with a plan number');
                    return;
                }
                const planNumber = match[1]; // preserves leading zeros

                const os = require('os');
                const crypto = require('crypto');

                const tmpDir = os.tmpdir();
                const tmpFileName = `makeplan-${crypto.randomUUID()}.md`;
                const tmpPath = path.join(tmpDir, tmpFileName);

                fs.writeFileSync(tmpPath, '', 'utf8');

                const doc = await vscode.workspace.openTextDocument(tmpPath);
                await vscode.commands.executeCommand('vscode.setEditorLayout', {
                    orientation: 0,
                    groups: [{ size: 0.5 }, { size: 0.5 }]
                });
                await vscode.window.showTextDocument(doc, { viewColumn: vscode.ViewColumn.Two });

                const saveHandler = vscode.workspace.onDidSaveTextDocument(async (savedDoc) => {
                    if (savedDoc.uri.toString() === doc.uri.toString()) {
                        saveHandler.dispose();

                        const content = savedDoc.getText().trim();

                        for (const group of vscode.window.tabGroups.all) {
                            for (const tab of group.tabs) {
                                if (tab.input instanceof vscode.TabInputText &&
                                    tab.input.uri.toString() === doc.uri.toString()) {
                                    await vscode.window.tabGroups.close(tab);
                                }
                            }
                        }

                        try { fs.unlinkSync(tmpPath); } catch (err) {}

                        if (content) {
                            const fullContent = `[${planNumber}] ${content}`;
                            const terminal = vscode.window.createTerminal({ name: 'Follow-Up Plan', shellPath: 'pwsh' });
                            terminal.show();
                            const escapedContent = fullContent.replace(/"/g, '`"');
                            terminal.sendText(`& "D:\\Repos\\_Personal\\Scripts\\AF2\\MakePlan.ps1" "${escapedContent}"`);
                        } else {
                            vscode.window.showInformationMessage('Follow-Up Plan cancelled - no content provided');
                        }
                    }
                });
            } catch (err) {
                vscode.window.showErrorMessage(`Follow-Up Plan failed: ${err.message}`);
            }
        })
    );

    // Make Plan - opens temp .md file in VSCode, then passes content to MakePlan.ps1
    context.subscriptions.push(
        vscode.commands.registerCommand('ivy.makePlan', async () => {
            try {
                const os = require('os');
                const crypto = require('crypto');

                // Create temp file with .md extension
                const tmpDir = os.tmpdir();
                const tmpFileName = `makeplan-${crypto.randomUUID()}.md`;
                const tmpPath = path.join(tmpDir, tmpFileName);

                // Create empty file
                fs.writeFileSync(tmpPath, '', 'utf8');

                // Open in VSCode - split editor vertically and open in bottom half
                const doc = await vscode.workspace.openTextDocument(tmpPath);
                await vscode.commands.executeCommand('vscode.setEditorLayout', {
                    orientation: 0, // vertical (top/bottom)
                    groups: [{ size: 0.5 }, { size: 0.5 }]
                });
                await vscode.window.showTextDocument(doc, { viewColumn: vscode.ViewColumn.Two });

                // Trigger on save — onDidCloseTextDocument is unreliable (VS Code delays document disposal)
                const saveHandler = vscode.workspace.onDidSaveTextDocument(async (savedDoc) => {
                    if (savedDoc.uri.toString() === doc.uri.toString()) {
                        saveHandler.dispose();

                        const content = savedDoc.getText().trim();

                        // Close the editor tab
                        for (const group of vscode.window.tabGroups.all) {
                            for (const tab of group.tabs) {
                                if (tab.input instanceof vscode.TabInputText &&
                                    tab.input.uri.toString() === doc.uri.toString()) {
                                    await vscode.window.tabGroups.close(tab);
                                }
                            }
                        }

                        // Clean up temp file
                        try {
                            fs.unlinkSync(tmpPath);
                        } catch (err) {
                            // Ignore cleanup errors
                        }

                        // Only proceed if user wrote something
                        if (content) {
                            const terminal = vscode.window.createTerminal({ name: 'Make Plan', shellPath: 'pwsh' });
                            terminal.show();
                            // Escape content for PowerShell - replace " with `"
                            const escapedContent = content.replace(/"/g, '`"');
                            terminal.sendText(`& "D:\\Repos\\_Personal\\Scripts\\AF2\\MakePlan.ps1" "${escapedContent}"`);
                        } else {
                            vscode.window.showInformationMessage('Make Plan cancelled - no content provided');
                        }
                    }
                });
            } catch (err) {
                vscode.window.showErrorMessage(`Make Plan failed: ${err.message}`);
            }
        })
    );
}

function deactivate() {}

module.exports = { activate, deactivate };
