// ur-browse — CLI for ur-Browse. All logic lives in UrKit's generic UrCLI; the command
// surface is defined once in BrowseSpec.
import UrBrowseSpec
import UrKit

UrCLI(BrowseSpec.spec).run()
