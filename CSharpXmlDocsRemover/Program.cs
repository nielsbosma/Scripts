using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;

namespace CSharpXmlDocsRemover;

class Program
{
    static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.WriteLine("Usage: CSharpXmlDocsRemover <file.cs> [file2.cs ...]");
            Console.WriteLine("       CSharpXmlDocsRemover --help");
            Console.WriteLine();
            Console.WriteLine("Removes XML documentation comments (/// and /** */) from C# files.");
            Console.WriteLine();
            Console.WriteLine("Options:");
            Console.WriteLine("  --dry-run    Show what would be removed without modifying files");
            Console.WriteLine("  --verbose    Show detailed processing information");
            return 1;
        }

        bool dryRun = false;
        bool verbose = false;
        var files = new List<string>();

        foreach (var arg in args)
        {
            if (arg == "--dry-run")
                dryRun = true;
            else if (arg == "--verbose")
                verbose = true;
            else if (arg == "--help")
            {
                Main(Array.Empty<string>());
                return 0;
            }
            else
                files.Add(arg);
        }

        if (files.Count == 0)
        {
            Console.Error.WriteLine("Error: No files specified");
            return 1;
        }

        int totalProcessed = 0;
        int totalRemoved = 0;

        foreach (var filePath in files)
        {
            if (!File.Exists(filePath))
            {
                Console.Error.WriteLine($"Error: File not found: {filePath}");
                continue;
            }

            if (!filePath.EndsWith(".cs", StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine($"Skipping non-C# file: {filePath}");
                continue;
            }

            try
            {
                var (removed, changed) = ProcessFile(filePath, dryRun, verbose);

                if (removed > 0)
                {
                    totalProcessed++;
                    totalRemoved += removed;

                    if (dryRun)
                        Console.WriteLine($"[DRY RUN] Would remove {removed} XML doc comment(s) from: {filePath}");
                    else
                        Console.WriteLine($"✓ Removed {removed} XML doc comment(s) from: {filePath}");
                }
                else
                {
                    if (verbose)
                        Console.WriteLine($"No XML documentation found in: {filePath}");
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Error processing {filePath}: {ex.Message}");
            }
        }

        if (totalProcessed > 0)
        {
            Console.WriteLine();
            Console.WriteLine($"Summary: {(dryRun ? "Would remove" : "Removed")} {totalRemoved} XML doc comment(s) from {totalProcessed} file(s)");
        }

        return 0;
    }

    static (int removed, bool changed) ProcessFile(string filePath, bool dryRun, bool verbose)
    {
        if (verbose)
            Console.WriteLine($"Processing: {filePath}");

        // Read the source file
        var source = File.ReadAllText(filePath);

        // Parse with Roslyn
        var tree = CSharpSyntaxTree.ParseText(source);
        var root = tree.GetRoot();

        // Apply the rewriter
        var rewriter = new RemoveXmlDocsRewriter();
        var newRoot = rewriter.Visit(root);
        var cleaned = newRoot!.ToFullString();

        int removed = rewriter.RemovedCount;
        bool changed = source != cleaned;

        // Write back if not dry run and something changed
        if (!dryRun && changed && removed > 0)
        {
            File.WriteAllText(filePath, cleaned);
        }

        return (removed, changed);
    }
}

class RemoveXmlDocsRewriter : CSharpSyntaxRewriter
{
    public int RemovedCount { get; private set; }

    public RemoveXmlDocsRewriter() : base(visitIntoStructuredTrivia: true)
    {
        RemovedCount = 0;
    }

    public override SyntaxTrivia VisitTrivia(SyntaxTrivia trivia)
    {
        if (trivia.IsKind(SyntaxKind.SingleLineDocumentationCommentTrivia) ||
            trivia.IsKind(SyntaxKind.MultiLineDocumentationCommentTrivia))
        {
            RemovedCount++;
            return default; // drop it
        }
        return base.VisitTrivia(trivia);
    }
}
