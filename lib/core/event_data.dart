part of bwu_dart.bwu_datagrid.core;

abstract class Events {
  static const HEADER_CELL_RENDERED = const EventType<HeaderCellRendered>(
      'header-cell-rendered');
  static const HEADER_ROW_CELL_RENDERED =
      const EventType<HeaderRowCellRendered>('header-row-cell-rendered');
  static const BEFORE_HEADER_CELL_DESTROY =
      const EventType<BeforeHeaderCellDestroy>('before-header-cell-destroy');
  static const SORT = const EventType<Sort>('sort');
  static const COLUMNS_RESIZED = const EventType<ColumnsResized>(
      'columns-resized');
  static const COLUMNS_REORDERED = const EventType<ColumnsReordered>(
      'columns-reordered');
  static const SELECTED_ROWS_CHANGED = const EventType<SelectedRowsChanged>(
      'selected-rows-changed');
  static const VIEWPORT_CHANGED = const EventType<ViewportChanged>(
      'viewport-changed');
  static const CELL_CSS_STYLES_CHANGED = const EventType<CellCssStylesChanged>(
      'cell-css-styles-changed');
  static const HEADER_MOUSE_ENTER = const EventType<HeaderMouseEnter>(
      'header-mouse-enter');
  static const HEADER_MOUSE_LEAVE = const EventType<HeaderMouseLeave>(
      'header-mouse-leave');
  static const HEADER_CONTEX_MENU = const EventType<HeaderContextMenu>(
      'header-context-menu');
  static const HEADER_CLICK = const EventType<HeaderClick>('header-click');
  static const ACTIVE_CELL_CHANGED = const EventType<ActiveCellChanged>(
      'active-cell-changed');
  static const BEFORE_CELL_EDITOR_DESTROY =
      const EventType<BeforeCellEditorDestroy>('before-cell-editor-destroy');
  static const BEFORE_EDIT_CELL = const EventType<BeforeEditCell>(
      'before-edit-cell');
  static const ACTIVE_CELL_POSITION_CHANGED =
      const EventType<ActiveCellPositionChanged>('active-cell-position-changed');
  static const CELL_CHANGED = const EventType<CellChanged>('cell-changed');
  static const ADD_NEW_ROW = const EventType<AddNewRow>('add-new-row');
  static const VALIDATION_ERROR = const EventType<ValidationError>(
      'validation-error');
  static const BEFORE_DESTROY = const EventType<BeforeDestroy>(
      'before-destroy');
  static const SCROLL = const EventType<Scroll>(
      'scroll');
  static const DRAG_INIT = const EventType<DragInit>(
      'drag-init');
  static const CLICK = const EventType<Click>('click');
  static const CONTEXT_MENU = const EventType<ContextMenu>('context-menu');
  static const DOUBLE_CLICK = const EventType<DoubleClick>('double-click');
  static const KEY_DOWN = const EventType<KeyDown>('key-down');
  static const MOUSE_ENTER = const EventType<MouseEnter>('mouse-enter');
  static const MOUSE_LEAVE = const EventType<MouseLeave>('mouse-leave');
  static const ROW_COUNT_CHANGED = const EventType<RowCountChanged>('row-count-changed');
  static const ROWS_CHANGED = const EventType<RowsChanged>('rows-changed');
  static const PAGING_INFO_CHANGED = const EventType<PagingInfoChanged>('paging-info-changed');
}

/***
 * An event object for passing data to event handlers and letting them control propagation.
 * <p>This is pretty much identical to how W3C and jQuery implement events.</p>
 * @class EventData
 * @constructor
 */

class EventData {
  var sender;
  dom.Event causedBy;
  Map detail;
  bool retVal = true;

  bool _isPropagationStopped = false;
  bool _isImmediatePropagationStopped = false;
  bool _isDefaultPrevented = false;

  /***
   * Returns whether stopPropagation was called on this event object.
   * @method isPropagationStopped
   * @return {Boolean}
   */
  bool get isPropagationStopped => _isPropagationStopped;

  /***
   * Stops event from propagating up the DOM tree.
   * @method stopPropagation
   */
  void stopPropagation() {
    _isPropagationStopped = true;
    if(causedBy != null) {
      causedBy.stopPropagation();
    }
  }

  /***
   * Stops event from propagating up the DOM tree.
   * @method stopPropagation
   */
  void preventDefault() {
    _isDefaultPrevented = true;
    if(causedBy != null) {
      causedBy.preventDefault();
    }
  }

  /***
   * Returns whether stopImmediatePropagation was called on this event object.\
   * @method isImmediatePropagationStopped
   * @return {Boolean}
   */
  bool get isImmediatePropagationStopped => _isImmediatePropagationStopped;

  /***
   * Prevents the rest of the handlers from being executed.
   * @method stopImmediatePropagation
   */
  void stopImmediatePropagation() {
    _isImmediatePropagationStopped = true;
    if(causedBy != null) {
      causedBy.stopImmediatePropagation();
    }
  }

  EventData({this.sender, this.detail, this.causedBy});
}

class BeforeHeaderCellDestroy extends EventData {
  dom.HtmlElement node;
  Column columnDef;

  BeforeHeaderCellDestroy(sender, dom.HtmlElement node, Column columnDef) :
      super(sender: sender, detail: {
        'node': node,
        'column': columnDef
      }) {
    this.node = node;
    this.columnDef = columnDef;
  }
}

class BeforeDestroy extends EventData {

  BeforeDestroy(sender) : super(sender: sender, detail: {});
}

class HeaderCellRendered extends EventData {
  dom.HtmlElement node;
  Column columnDef;

  HeaderCellRendered(sender, dom.HtmlElement node, Column columnDef) : super(
      sender: sender, detail: {
        'node': node,
        'column': columnDef
      }) {
    this.node = node;
    this.columnDef = columnDef;
  }
}

class HeaderRowCellRendered extends EventData {

  HeaderRowCellRendered(sender) : super(sender: sender, detail: {});
}

class Sort extends EventData {
  bool multiColumnSort;
  Column sortColumn;
  Map<Column,bool> sortColumns;
  bool sortAsc;

  Sort(sender, bool multiColumnSort, Column sortColumn, Map<Column,bool> sortColumns, bool sortAsc, dom.Event
      causedBy)
      : super(sender: sender, causedBy: causedBy, detail: {
        'multiColumnSort': multiColumnSort,
        'sortColumn': sortColumn,
        'sortAsc': sortAsc,
      }) {
    this.multiColumnSort = multiColumnSort;
    this.sortColumn = sortColumn;
    this.sortAsc = sortAsc;
  }
}

class ColumnsResized extends EventData {

  ColumnsResized(sender) : super(sender: sender, detail: {});
}

class ColumnsReordered extends EventData {

  ColumnsReordered(sender) : super(sender: sender, detail: {});
}

class SelectedRowsChanged extends EventData {
  List<int> rows;
  dom.CustomEvent get causedBy => super.causedBy;

  SelectedRowsChanged(sender, rows, causedBy) : super(sender: sender, causedBy: causedBy, detail: {'rows': rows}) {
    this.rows = rows;
  }
}

class ViewportChanged extends EventData {

  ViewportChanged(sender) : super(sender: sender, detail: {});
}

class CellCssStylesChanged extends EventData {
  String key;
  String hash;

  CellCssStylesChanged(sender, String key, {String hash}) : super(sender: sender, detail: {'key': key, 'hash': hash}) {
    this.key = key;
    this.hash = hash;
  }
}

class HeaderMouseEnter extends EventData {
  Column data;
  dom.MouseEvent get causedBy => super.causedBy;

  HeaderMouseEnter(sender, Column data, {dom.MouseEvent causedBy}) : super(sender: sender, causedBy: causedBy, detail: {'data': data}) {
    this.data = data;
  }
}

class HeaderMouseLeave extends EventData {
  String data;
  dom.MouseEvent get causedBy => super.causedBy;

  HeaderMouseLeave(sender, String data, {dom.MouseEvent causedBy}) : super(sender: sender, causedBy: causedBy, detail: {'data': data}) {
    this.data = data;
  }
}

class HeaderContextMenu extends EventData {
  Column column;
  dom.MouseEvent get causedBy => super.causedBy;

  HeaderContextMenu(sender, Column column, {dom.MouseEvent causedBy}) : super(sender: sender, causedBy: causedBy, detail: {'column': column}) {
    this.column = column;
  }
}

class HeaderClick extends EventData {
  Column column;
  dom.MouseEvent get causedBy => super.causedBy;

  HeaderClick(sender, Column column, {dom.MouseEvent causedBy}) : super(sender: sender, causedBy: causedBy, detail: {'column': column}) {
    this.column = column;
  }
}

class ActiveCellChanged extends EventData {
  Cell cell; // these members should all be final and the constructor const;

  ActiveCellChanged(sender, Cell cell) : super(sender: sender, detail: {'cell': cell}) {
    this.cell = cell;
  }
}

class BeforeCellEditorDestroy extends EventData {
  Editor editor;
  BeforeCellEditorDestroy(sender, Editor editor) : super(sender: sender, detail: {'editor': editor}) {
    this.editor = editor;
  }
}

class BeforeEditCell extends EventData {
  Cell cell;
  /*Map/Item*/ dynamic item;
  Column column;
  BeforeEditCell(sender, {Cell cell, /*Map/Item*/ dynamic item, Column column}) : super(sender: sender, detail: {'cell': cell, 'item': item, 'column':column}) {
    this.cell = cell;
    this.item = item;
    this.column = column;
  }
}

class ActiveCellPositionChanged extends EventData {

  ActiveCellPositionChanged(sender) : super(sender: sender, detail: {});
}

class CellChanged extends EventData {
  Cell cell;
  /*Map/Item*/ dynamic item;
  CellChanged(sender, Cell cell, /*Map/Item*/ dynamic item) : super(sender: sender, detail: {'cell': cell, 'item': item}) {
    this.cell = cell;
    this.item = item;
  }
}

class AddNewRow extends EventData {
  /*Map/Item*/ dynamic item;
  Column column;
  AddNewRow(sender, /*Map/Item*/ dynamic item, Column column) : super(sender: sender, detail: {'item': item, 'column': column}) {
    this.item = item;
    this.column = column;
  }
}

class ValidationError extends EventData {
  Editor editor;
  dom.HtmlElement cellNode;
  ValidationResult validationResults;
  Cell cell;
  Column column;
  ValidationError(sender, {Editor editor,
    dom.HtmlElement cellNode,
    ValidationResult validationResults,
    Cell cell,
    Column column}) : super(sender: sender, detail: {
      'editor': editor,
      'cellNode': cellNode,
      'validatoinResults': validationResults,
      'cell': cell,
      'column': column
    });
}

class Scroll extends EventData {
  int scrollLeft;
  int scrollTop;

  Scroll(sender, {int scrollLeft, int scrollTop}) : super(sender: sender, detail: {'scrollLeft': scrollLeft, 'scrollTop': scrollTop}) {
    this.scrollLeft = scrollLeft;
    this.scrollTop = scrollTop;
  }
}

class DragInit extends EventData {
  int dd;
  dom.MouseEvent get causedBy => super.causedBy;
  bool retVal = false;

  DragInit(sender, {int dd, dom.MouseEvent causedBy}) : super(sender: sender, causedBy: causedBy, detail: {'dd': dd}) {
    this.dd = dd;
  }
}

class Click extends EventData {
  Cell cell;
  dom.MouseEvent get causedBy => super.causedBy;

  Click(sender, Cell cell,  {dom.MouseEvent causedBy}) : super(sender: sender, causedBy: causedBy, detail: {'cell': cell}) {
    this.cell = cell;
  }
}

class ContextMenu extends EventData {
  Cell cell;
  dom.MouseEvent get causedBy => super.causedBy;

  ContextMenu(sender, Cell cell,  {dom.MouseEvent causedBy}) : super(sender: sender, causedBy: causedBy, detail: {'cell': cell}) {
    this.cell = cell;
  }
}

class DoubleClick extends EventData {
  Cell cell;
  dom.MouseEvent get causedBy => super.causedBy;

  DoubleClick(sender, Cell cell,  {dom.MouseEvent causedBy}) : super(sender: sender, causedBy: causedBy, detail: {'cell': cell}) {
    this.cell = cell;
  }
}

class KeyDown extends EventData {
  Cell cell;
  dom.KeyboardEvent get causedBy => super.causedBy;

  KeyDown(sender, Cell cell, {dom.KeyboardEvent causedBy}) : super(sender: sender, causedBy: causedBy, detail: {'cell': cell}) {
    this.cell = cell;
  }
}

class MouseEnter extends EventData {
  dom.MouseEvent get causedBy => super.causedBy;

  MouseEnter(sender,  {dom.MouseEvent causedBy}) : super(sender: sender, causedBy: causedBy);
}

class MouseLeave extends EventData {
  dom.MouseEvent get causedBy => super.causedBy;

  MouseLeave(sender,  {dom.MouseEvent causedBy}) : super(sender: sender, causedBy: causedBy );
}


class RowCountChanged extends EventData {}

class RowsChanged extends EventData {}

class PagingInfoChanged extends EventData {}