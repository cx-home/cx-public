import * as path from 'path';
import * as fs from 'fs';
import { workspace, ExtensionContext, window } from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;

export function activate(context: ExtensionContext) {
  const serverPath = resolveLspServer(context);
  if (!serverPath) {
    window.showWarningMessage(
      'CX: language server not found. Run `make build-lsp` in the repo root.'
    );
    return;
  }

  const serverOptions: ServerOptions = {
    run:   { command: 'node', args: [serverPath], transport: TransportKind.stdio },
    debug: { command: 'node', args: [serverPath], transport: TransportKind.stdio },
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: 'file', language: 'cx' }],
    synchronize: {
      fileEvents: workspace.createFileSystemWatcher('**/*.cx'),
    },
  };

  client = new LanguageClient('cx', 'CX Language Server', serverOptions, clientOptions);
  client.start();
  context.subscriptions.push({ dispose: () => client?.stop() });
}

export function deactivate(): Thenable<void> | undefined {
  return client?.stop();
}

function resolveLspServer(context: ExtensionContext): string | undefined {
  // 1. Next to this extension (installed/packaged)
  const bundled = context.asAbsolutePath(path.join('..', 'lsp', 'out', 'server.js'));
  if (fs.existsSync(bundled)) return bundled;

  // 2. Workspace setting override
  const cfg = workspace.getConfiguration('cx');
  const override = cfg.get<string>('languageServerPath');
  if (override && fs.existsSync(override)) return override;

  return undefined;
}
