"""
Interactive demo for Neo4j MAF Provider capabilities.

Run with: uv run start-samples
Or directly: uv run start-samples 1  (for demo 1)
"""

import argparse
import asyncio
import sys
from collections.abc import Awaitable, Callable

from dotenv import load_dotenv

from .env import get_env_file_path
from .utils import print_header

# Demo function type
DemoFunc = Callable[[], Awaitable[None]]


def _get_demos() -> dict[str, DemoFunc]:
    """Lazy load demo functions to avoid circular imports."""
    from samples.basic_fulltext.main import demo_context_provider_basic
    from samples.graph_enriched.main import demo_context_provider_graph_enriched
    from samples.mcp_tools.main import demo_mcp_tools
    from samples.mcp_write_test.main import demo_mcp_write_test
    from samples.vector_search.main import demo_context_provider_vector
    from samples.vector_search.semantic_search import demo_semantic_search

    return {
        "1": demo_semantic_search,
        "2": demo_context_provider_basic,
        "3": demo_context_provider_vector,
        "4": demo_context_provider_graph_enriched,
        "5": demo_mcp_tools,
        "6": demo_mcp_write_test,
    }


def print_menu() -> str | None:
    """Display menu and get user selection."""
    print_header("Neo4j MAF Provider Demo")
    print("Select a demo to run:\n")
    print("  -- Financial Documents Database --")
    print("  1. Semantic Search")
    print("  2. Context Provider (Fulltext) [NOT WORKING]")
    print("  3. Context Provider (Vector)")
    print("  4. Context Provider (Graph-Enriched)")
    print("")
    print("  -- MCP Server Integration --")
    print("  5. MCP Tools (Neo4j via MCP Server)")
    print("  6. MCP Write Test (Verify Read-Only Mode)")
    print("")
    print("  A. Run all demos (skips #2)")
    print("  0. Exit\n")

    try:
        choice = input("Enter your choice (0-6, A): ").strip().upper()
        if choice in ("0", "1", "2", "3", "4", "5", "6", "A"):
            return choice
        else:
            print("\nInvalid choice. Please enter 0-6 or A.")
            return None
    except (KeyboardInterrupt, EOFError):
        print("\n")
        return "0"


async def run_demo(choice: str) -> None:
    """Run the selected demo."""
    demos = _get_demos()
    if choice == "A":
        # Run all demos sequentially (skip demo 2 - fulltext not working)
        working_demos = {k: v for k, v in demos.items() if k != "2"}
        demo_list = list(working_demos.values())
        for i, demo_func in enumerate(demo_list):
            await demo_func()
            if i < len(demo_list) - 1:
                print("\n" + "=" * 60 + "\n")
    elif choice in demos:
        await demos[choice]()


def main() -> None:
    """Main entry point for the demo CLI."""
    parser = argparse.ArgumentParser(
        description="Neo4j MAF Provider Demo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  uv run start-samples        Interactive menu
  uv run start-samples 1      Run demo 1 (Semantic Search)
  uv run start-samples 2      Run demo 2 (Context Provider - Fulltext) [NOT WORKING]
  uv run start-samples 3      Run demo 3 (Context Provider - Vector)
  uv run start-samples 4      Run demo 4 (Context Provider - Graph-Enriched)
  uv run start-samples 5      Run demo 5 (MCP Tools - Neo4j via MCP Server)
  uv run start-samples 6      Run demo 6 (MCP Write Test - Verify Read-Only Mode)
  uv run start-samples a      Run all demos (skips #2)
""",
    )
    parser.add_argument(
        "demo",
        nargs="?",
        type=str,
        choices=["1", "2", "3", "4", "5", "6", "a", "A"],
        help="Demo to run: 1-4=Financial Documents, 5-6=MCP Server, a=All",
    )
    args = parser.parse_args()

    # Load environment
    env_file = get_env_file_path()
    if env_file:
        load_dotenv(env_file)
        print(f"Loaded environment from: {env_file}")
    else:
        print("Using system environment variables")

    # If demo specified on command line, run it directly
    if args.demo:
        try:
            asyncio.run(run_demo(args.demo.upper()))
        except KeyboardInterrupt:
            print("\n\nDemo interrupted.")
        return

    # Interactive menu mode
    while True:
        choice = print_menu()

        if choice is None:
            continue
        elif choice == "0":
            print("\nGoodbye!")
            sys.exit(0)
        else:
            try:
                asyncio.run(run_demo(choice))
            except KeyboardInterrupt:
                print("\n\nDemo interrupted.")

            input("\nPress Enter to continue...")


if __name__ == "__main__":
    main()
