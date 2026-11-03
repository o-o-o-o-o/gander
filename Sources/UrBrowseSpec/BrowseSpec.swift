import Foundation
#if canImport(UrKit)
import UrKit
#endif

/// The one definition of Ur Browse's command surface, shared by the app (URL-scheme routing,
/// verb validation) and the CLI (pot-vs-verb disambiguation, usage). Adding a verb means
/// adding it here and handling it in `BrowseCommand` — nowhere else.
public enum BrowseSpec {
    public static let verbs: Set<String> = [
        "toggle", "show", "hide",
        "picker", "sites", "next", "prev",
        "open", "site", "current",
        "frame", "menubar",
        "slip", "info", "quit",
    ]

    public static let spec = UrAppSpec(
        app: "browse",
        command: "ur-browse",
        bundleID: "io.ur.browse",
        appExecutable: "UrBrowse",
        devExecutable: "UrBrowseApp",
        installedAppPath: "/Applications/Ur Browse.app",
        schemes: ["ur-browse", "gander"],
        verbs: verbs,
        booleanFlags: ["list"],
        defaultVerb: "toggle",
        autostartVerbs: ["toggle", "show", "open", "site", "picker"],
        throwOptions: ["glaze": "glaze", "url": "defaultUrl"],
        usage: usage
    )

    public static let usage = """
        Usage: ur-browse [pot] <command> [args] [options]

        Pots (instances):
          ur-browse pots [--json]                  list pots and whether they are running
          ur-browse throw <pot> [--glaze #hex] [--url u] [--from pot] [--login] [--no-start]
          ur-browse <pot> start                    start a stopped pot
          ur-browse <pot> quit

        Window:
          ur-browse [pot] toggle | show | hide     (show takes frame options)
          ur-browse [pot] frame <preset> | frame --x v --y v --width v --height v
          ur-browse [pot] menubar                  restore a hidden menu bar icon

        Sites (addressable by id):
          ur-browse [pot] site <id>[/path]         open a site, optionally deep-linked
          ur-browse [pot] sites --json | --alfred | --list
          ur-browse [pot] picker                   toggle the site picker (also: bare `sites`)
          ur-browse [pot] next | prev
          ur-browse [pot] open <url> [--shortcut 1-9]
          ur-browse [pot] current [--json]         active site, URL and title

        Slip (user scripts in ~/.config/ur/browse/<pot>/slip/):
          ur-browse [pot] slip [--list]            reload slip scripts (or list them)

          ur-browse [pot] info --json

        Frame values: points (420), percent (30%), or full/100%; --x/--y also take
        left/right/top/bottom. Omit [pot] for the default pot.

        URL scheme: ur-browse://[pot/]<command>[/args…][?option=value]
          e.g. ur-browse://work/site/gh/o-o-o-o-o/ur-browse
        """
}
