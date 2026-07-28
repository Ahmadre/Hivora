/// Lexical, configured the way hinata stores documents.
///
/// The server persists Lexical JSON and converts every other input format —
/// markdown from MCP agents, HTML from inbound e-mail — on the way in. This is
/// the matching registry on the client: every node type the server can emit,
/// and only those.
///
/// The registry is closed at construction, so a type nobody registered here
/// cannot be opened. That is the point rather than a limitation: it turns "the
/// server started writing a node the app does not understand" into a loud
/// failure in a test instead of a blank article in production.
library;

import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

import 'callout_node.dart';
import 'smart_link_node.dart';

export 'callout_node.dart';
export 'smart_link_node.dart';

/// Every node type a stored hinata document may contain.
///
/// The bundle's own types plus the two that are genuinely hinata's: the
/// `{{issue:…}}` chip and the `:::info` callout, which used to be markdown
/// syntax found by a regex and are node types now. The horizontal rule was
/// declared here too until the port grew one of its own; `lexicalNodes`
/// registers it now.
List<NodeSpec<LexicalNode>> get hinataNodes => <NodeSpec<LexicalNode>>[
  ...lexicalNodes,
  const NodeSpec<SmartLinkNode>(type: 'smartlink', create: SmartLinkNode.new),
  const NodeSpec<CalloutNode>(type: 'callout', create: CalloutNode.new),
];

/// Creates an editor that understands every stored hinata document.
LexicalEditor createHinataEditor({
  EditorConfig config = const EditorConfig(),
  EditorState? initialEditorState,
}) => LexicalEditor(
  nodes: hinataNodes,
  config: config,
  initialEditorState: initialEditorState,
);

/// The node types a reader can tap: links, mentions, and hinata's own chips.
const Set<String> hinataInteractiveNodeTypes = {
  ...interactiveNodeTypes,
  'smartlink',
};
