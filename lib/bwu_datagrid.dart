library bwu_dart.bwu_datagrid.datagrid;

import 'dart:async' as async;
import 'dart:math' as math;
import 'dart:html' as dom;

import 'package:polymer/polymer.dart';

import 'package:bwu_datagrid/core/core.dart' as core;
//import 'dataview/dataview.dart';
import 'package:bwu_datagrid/plugins/plugin.dart';

import 'package:bwu_datagrid/datagrid/helpers.dart';
import 'package:bwu_datagrid/editors/editors.dart';
import 'package:bwu_datagrid/datagrid/bwu_datagrid_headerrow_column.dart';
import 'package:bwu_datagrid/datagrid/bwu_datagrid_header_column.dart';
import 'package:bwu_datagrid/datagrid/bwu_datagrid_headers.dart';
import 'package:bwu_datagrid/dataview/dataview.dart';
import 'package:bwu_datagrid/tools/html.dart' as tools;
import 'package:bwu_datagrid/formatters/formatters.dart';



@CustomTag('bwu-datagrid')
class BwuDatagrid extends PolymerElement {

  BwuDatagrid.created() : super.created();

  @override
  void attached() {
    try {
      super.attached();
      new async.Future(() {
//        init();
//        render();
      });
    }catch(e) {
      print('BwuDataGrid.enteredView(): $e');
    }
  }

  // DataGrid(dom.HtmlElement container, String data, int columns, Options options);
  List<Map> _dataMap;
  @published List<Map> get dataMap => _dataMap;
  set dataMap(List<Map> val) => setDataMap(val, true);

  DataView _dataView;
  @published DataView get dataView => _dataView;
  set dataView(DataView val) => setDataView(val, true);

  List<Column> _columns;
  @published List<Column> get columns => _columns;

  @published GridOptions _gridOptions = new GridOptions();

  // settings
  static final Column _columnDefaults = new Column();

  //dom.NodeValidator nodeValidator = new dom.NodeValidatorBuilder.common();

  // scroller
  int th;   // virtual height
  double h;    // real scrollable height
  double ph;   // page height
  int n;    // number of pages
  double cj;   // "jumpiness" coefficient

  int page = 0;       // current page
  int pageOffset = 0;     // current page offset
  int vScrollDir = 1;

  // shared across all grids on the page
  math.Point scrollbarDimensions;
  int maxSupportedCssHeight;  // browser's breaking point

  // private
  bool _initialized = false;
  dom.ShadowRoot _container;
  //String uid = "bwu_datagrid_${(1000000 * new math.Random().nextDouble()).round()}";
  dom.HtmlElement _focusSink, _focusSink2;
  dom.HtmlElement _headerScroller;
  BwuDatagridHeaders _headers;
  dom.HtmlElement _headerRow, _headerRowScroller, _headerRowSpacer;
  dom.HtmlElement _topPanelScroller;
  dom.HtmlElement _topPanel;
  dom.HtmlElement _viewport;
  dom.HtmlElement _canvas;
  dom.StyleElement _style;
  dom.HtmlElement _boundAncestors;
  dom.CssStyleSheet _stylesheet;
  Map<int,dom.CssStyleRule> _columnCssRulesL, _columnCssRulesR;
  int _viewportH = 0;
  int _viewportW = 0;
  int _canvasWidth;
  bool _viewportHasHScroll = false, _viewportHasVScroll = false;
  int _headerColumnWidthDiff = 0, _headerColumnHeightDiff = 0, // border+padding
      _cellWidthDiff = 0, _cellHeightDiff = 0;
  int _absoluteColumnMinWidth;

  int _tabbingDirection = 1;
  int _activePosX;
  int _activeRow, _activeCell;
  dom.HtmlElement _activeCellNode = null;
  Editor _currentEditor = null;
  dynamic _serializedEditorValue;
  EditController _editController;

  Map<int,RowCache> _rowsCache = {};
  int _renderedRows = 0;
  int _numVisibleRows;
  int _prevScrollTop = 0;
  int _scrollTop = 0;

  int _lastRenderedScrollTop = 0;
  int _lastRenderedScrollLeft = 0;
  int _prevScrollLeft = 0;
  int _scrollLeft = 0;

  SelectionModel _selectionModel;
  List<int> _selectedRows = [];

  List<Plugin> _plugins = [];
  Map<String,Map<int,String>> _cellCssClasses = {};

  Map<String,int> _columnsById = {};
  List<SortColumn> _sortColumns = [];
  List<int> _columnPosLeft = [];
  List<int> _columnPosRight = [];


  // async call handles
  async.Timer _h_editorLoader = null;
  async.Timer _h_render = null;
  async.Timer _h_postrender = null;
  List<List<int>> _postProcessedRows = [];
  int _postProcessToRow = null;
  int _postProcessFromRow = null;

  // perf counters
  int _counter_rows_rendered = 0;
  int _counter_rows_removed = 0;

  // These two variables work around a bug with inertial scrolling in Webkit/Blink on Mac.
  // See http://crbug.com/312427.
  dom.HtmlElement _rowNodeFromLastMouseWheelEvent;  // this node must not be deleted while inertial scrolling
  dom.HtmlElement _zombieRowNodeFromLastMouseWheelEvent;  // node that was hidden instead of getting deleted

  final core.EventBus _eventBus = new core.EventBus();


  void setup({List<Map> dataMap, DataView dataView, List<Column> columns, GridOptions gridOptions}) {
    if(dataMap != null && dataView != null) {
      throw 'Only one of dataMap or dataView can be used at a time.';
    }
    if(_initialized) {
      if(dataMap != null) {
        this.dataMap = dataMap;
      }
      if(dataView != null) {
        this.dataView = dataView;
      }
      if(columns != null) {
        setColumns = columns;
      }
      if(gridOptions != null) {
        setGridOptions = gridOptions;
      }
    } else {
      _dataMap = dataMap;
      _dataView = dataView;
      _columns = columns;
      _gridOptions = gridOptions;
    }
    init();
    render();
  }

  //////////////////////////////////////////////////////////////////////////////////////////////
  // Initialization


  void init() {
    _container = this.shadowRoot;

    // calculate these only once and share between grid instances
    maxSupportedCssHeight = maxSupportedCssHeight != null ? maxSupportedCssHeight : _getMaxSupportedCssHeight();
    scrollbarDimensions = scrollbarDimensions != null ? scrollbarDimensions : _measureScrollbar();

    //options = $.extend({}, defaults, options);
    _validateAndEnforceOptions();
    _columnDefaults.width = _gridOptions.defaultColumnWidth;

    _columnsById = {};
    if(columns != null) {
      for (int i = 0; i < columns.length; i++) {
        Column m = new Column()..extend(_columnDefaults)..extend(columns[i]); // TODO extend
        columns[i] = m;
        _columnsById[m.id] = i;
        if (m.minWidth != null && m.width < m.minWidth) {
          m.width = m.minWidth;
        }
        if (m.maxWidth != null && m.width > m.maxWidth) {
          m.width = m.maxWidth;
        }
        //dom.document.head.append(new dom.StyleElement());
      }
    }

// TODO port jQuery UI sortable
//    // validate loaded JavaScript modules against requested options
//    if (gridOptions.enableColumnReorder && !$.fn.sortable) {
//      throw "DataGrid's 'enableColumnReorder = true' option requires jquery-ui.sortable module to be loaded";
//    }

    _editController = new EditController(_commitCurrentEdit, _cancelCurrentEdit);

    //$container
        //..children.clear(); // TODO empty()
    this
        ..style.overflow = 'hidden'
        ..style.outline = '0'
        ..style.display = 'block' // TODO should be inside the style tag
        //..classes.add(uid)
        ..classes.add("ui-widget");

    // set up a positioning container if needed
//      if (!/relative|absolute|fixed/.test($container.css("position"))) {
//        $container.css("position", "relative");
//      }
    if(!this.style.position.contains(new RegExp('relative|absolute|fixed'))) {
      this.style.position = 'relative';
    }

    _focusSink = new dom.DivElement()
      ..tabIndex=0
      //..hideFocus=true // IE
      ..style.position = 'fixed'
      ..style.width='0'
      ..style.height='0'
      ..style.top='0'
      ..style.left='0'
      ..style.outline='0';
    _container.append(_focusSink);

    _headerScroller = new dom.DivElement()
      ..classes.add('bwu-datagrid-header')
      ..classes.add('ui-state-default')
      ..style.overflow ='hidden'
      ..style.position='relative';
    _container.append(_headerScroller);

    _headers = (new dom.Element.tag('bwu-datagrid-headers') as BwuDatagridHeaders)
      ..classes.add('bwu-datagrid-header-columns')
      ..style.left = '-1000px';
    _headerScroller.append(_headers);
    _headers.style.width = "${_getHeadersWidth()}px";

    _headerRowScroller = new dom.DivElement()
      ..classes.add('bwu-datagrid-headerrow')
      ..classes.add('ui-state-default')
      ..style.overflow = 'hidden'
      ..style.position='relative';
    _container.append(_headerRowScroller);

    _headerRow = new dom.DivElement()
      ..classes.add('bwu-datagrid-headerrow-columns');
    _headerRowScroller.append(_headerRow);

    _headerRowSpacer = new dom.DivElement()
      ..style.display = 'block'
      ..style.height ='1px'
      ..style.position ='absolute'
      ..style.top ='0'
      ..style.left='0'
        ..style.width = '${_getCanvasWidth() + scrollbarDimensions.x}px';
    _headerRowScroller.append(_headerRowSpacer);

    _topPanelScroller = new dom.DivElement()
      ..classes.add('bwu-datagrid-top-panel-scroller')
      ..classes.add('ui-state-default')
      ..style.overflow ='hidden'
      ..style.position='relative';
    _container.append(_topPanelScroller);
    _topPanel = new dom.DivElement()
      ..classes.add('bwu-datagrid-top-panel')
      ..style.width='10000px';
    _topPanelScroller.append(_topPanel);

    if (!_gridOptions.showTopPanel) {
      _topPanelScroller.style.display = 'none'; //hide();
    }

    if (!_gridOptions.showHeaderRow) {
      _headerRowScroller.style.display = 'none'; // hide();
    }

    _viewport = new dom.DivElement()
      ..classes.add('bwu-datagrid-viewport')
      ..style.width='100%'
      ..style.overflow ='auto'
      ..style.outline='0'
      ..style.position='relative';
    _container.append(_viewport);
    _viewport.style.overflowY = _gridOptions.autoHeight ? "hidden" : "auto";

    _canvas = new dom.DivElement()..classes.add('grid-canvas');
    _viewport.append(_canvas);

    _focusSink2 = _focusSink.clone(true);
    _container.append(_focusSink2);

    if (!_gridOptions.explicitInitialization) {
      _finishInitialization();
    }
  }

  void _finishInitialization() {
    if (!_initialized) {
      _initialized = true;

      _viewportW = this.offsetWidth; //tools.parseInt(this.getComputedStyle().width);

      // header columns and cells may have different padding/border skewing width calculations (box-sizing, hello?)
      // calculate the diff so we can set consistent sizes
      _measureCellPaddingAndBorder();

      // for usability reasons, all text selection in BwuDatagrid is disabled
      // with the exception of input and textarea elements (selection must
      // be enabled there so that editors work as expected); note that
      // selection in grid cells (grid body) is already unavailable in
      // all browsers except IE
      _disableSelection(_headers); // disable all text selection in header (including input and textarea)

      if (!_gridOptions.enableTextSelectionOnCells) {
        // disable text selection in grid cells except in input and textarea elements
        // (this is IE-specific, because selectstart event will only fire in IE)
        _viewport.onSelectStart.listen((event) {  //  bind("selectstart.ui",
          return event.target is dom.InputElement || event.target is dom.TextAreaElement;
        });
      }

      _updateColumnCaches();
      _createColumnHeaders();
      _setupColumnSort();
      _createCssRules();
      resizeCanvas();
      _bindAncestorScrollEvents();

      _container.on["resize.bwu-datagrid"].listen(resizeCanvas); // TODO event name seems wrong
      //$viewport
          //.bind("click", handleClick)
      _viewport.onScroll.listen(_handleScroll);
      _headerScroller..onContextMenu.listen(_handleHeaderContextMenu)
          ..onClick.listen(_handleHeaderClick)
          ..querySelectorAll(".bwu-datagrid-header-column").forEach((e) {
            (e as dom.HtmlElement)
            ..onMouseEnter.listen(_handleHeaderMouseEnter)
            ..onMouseLeave.listen(_handleHeaderMouseLeave);
      });
      _headerRowScroller
          .onScroll.listen(_handleHeaderRowScroll);
      _focusSink
          ..append(_focusSink2)
          ..onKeyDown.listen(_handleKeyDown);
      _canvas
          ..onKeyDown.listen(_handleKeyDown)
          ..onClick.listen(_handleClick)
          ..onDoubleClick.listen(_handleDblClick)
          ..onContextMenu.listen(_handleContextMenu)
          ..onDrag.listen(_handleDrag)
          //..bind("draginit", handleDragInit) // TODO special jQuery event before DragStart (click)
          ..onDragStart.listen((e) {/*{distance: 3}*/; _handleDragStart(e, {'distance': 3});}) // TODO what is distance?
          ..onDragOver.listen(_handleDrag)
          ..onDragEnd.listen(_handleDragEnd);
//          ..querySelectorAll(".bwu-datagrid-cell").forEach((e) {
//            (e as dom.HtmlElement)
//              ..onMouseEnter.listen(handleMouseEnter)
//              ..onMouseLeave.listen(handleMouseLeave);
//          });

      // Work around http://crbug.com/312427.
      if (dom.window.navigator.userAgent.toLowerCase().contains('webkit') &&
          dom.window.navigator.userAgent.toLowerCase().contains('macintosh')) {
        _canvas.onMouseWheel.listen(_handleMouseWheel);
      }
    }
  }

  void registerPlugin(Plugin plugin) {
    _plugins.insert(0, plugin);
    plugin.init(this);
  }

  void unregisterPlugin(Plugin plugin) {
    for (var i = _plugins.length; i >= 0; i--) {
      if (_plugins[i] == plugin) {
        _plugins[i].destroy();
        _plugins.removeAt(i);
        break;
      }
    }
  }

  async.StreamSubscription _onSelectedRangesChanged;

  set setSelectionModel(SelectionModel model) {
    if (_selectionModel != null) {
      if(_onSelectedRangesChanged != null) {
        _onSelectedRangesChanged.cancel(); //selectionModel.onSelectedRangesChanged.unsubscribe(handleSelectedRangesChanged);
      }
      _selectionModel.destroy();
    }

    _selectionModel = model;
    if (_selectionModel != null) {
      _selectionModel.init(this);
      _onSelectedRangesChanged = _selectionModel.onSelectedRangesChanged.listen(_selectedRangesChangedHandler);
    }
  }

  SelectionModel get getSelectionModel => _selectionModel;

  dom.HtmlElement get getCanvasNode => _canvas;

  math.Point _measureScrollbar() {
    dom.HtmlElement $c = new dom.DivElement()
      ..style.position = 'absolute'
      ..style.top ='-10000px'
      ..style.left = '10000px'
      ..style.width = '100px'
      ..style.height ='100px'
      ..style.overflow = 'scroll';
    dom.document.body.append($c);
    var cCs = $c.getComputedStyle();
    var dim = new math.Point(tools.parseInt(cCs.width) - $c.clientWidth, tools.parseInt(cCs.height) - $c.clientHeight);
    $c.remove();
    return dim;
  }

  int _getHeadersWidth() {
    var headersWidth = 0;
    int ii = columns != null ? columns.length : 0;
    for (int i = 0;  i < ii; i++) {
      int width = columns[i].width;
      headersWidth += width;
    }
    headersWidth += scrollbarDimensions.x;
    return math.max(headersWidth, _viewportW) + 1000;
  }

  int _getCanvasWidth() {
    int availableWidth = _viewportHasVScroll ? _viewportW - scrollbarDimensions.x : _viewportW;
    int rowWidth = 0;
    int i = columns != null ? columns.length : 0;
    while (i-- > 0) {
      rowWidth += columns[i].width;
    }
    return _gridOptions.fullWidthRows ? math.max(rowWidth, availableWidth) : rowWidth;
  }

  void _updateCanvasWidth(forceColumnWidthsUpdate) {
    int oldCanvasWidth = _canvasWidth;
    _canvasWidth = _getCanvasWidth();

    if (_canvasWidth != oldCanvasWidth) {
      _canvas.style.width = "${_canvasWidth}px";
      _headerRow.style.width = "${_canvasWidth}px";
      _headers.style.width = "${_getHeadersWidth()}px";
      _viewportHasHScroll = (_canvasWidth > _viewportW - scrollbarDimensions.x);
    }

    _headerRowSpacer.style.width = "${(_canvasWidth + (_viewportHasVScroll ? scrollbarDimensions.x : 0))}px";

    if (_canvasWidth != oldCanvasWidth || forceColumnWidthsUpdate) {
      _applyColumnWidths();
    }
  }

  void _disableSelection(dom.HtmlElement $target) {
    if ($target != null) {
      $target
        ..attributes["unselectable"] = "on"
        ..style.userSelect= "none"
        ..onSelectStart.listen((e) {
          e
           ..stopPropagation()
           ..stopImmediatePropagation();
        }); // bind("selectstart.ui", function () {
    }
  }

  int _getMaxSupportedCssHeight() {
    int supportedHeight = 1000000;
    // FF reports the height back but still renders blank after ~6M px
    int testUpTo = dom.window.navigator.userAgent.toLowerCase().contains('firefox') ? 6000000 : 1000000000; // TODO check match
    var div = new dom.DivElement()..style.display='none';
    dom.document.body.append(div);

    while (true) {
      int test = supportedHeight * 2;
      div.style.height = "${test}px";
      if (test > testUpTo || div.getComputedStyle().height != "${test}px") {
        break;
      } else {
        supportedHeight = test;
      }
    }

    div.remove();
    return supportedHeight;
  }

  List<async.StreamSubscription> _scrollSubscription = [];

  // TODO:  this is static.  need to handle page mutation.
  void _bindAncestorScrollEvents() {
    var $elem = _canvas;

    if($elem.parentNode is dom.ShadowRoot) {
      $elem = ($elem.parentNode as dom.ShadowRoot).host;
    } else {
      $elem = $elem.parent;
    }

    while ($elem != this && $elem != null) {
      // bind to scroll containers only
      if ($elem == _viewport || $elem.scrollWidth != $elem.clientWidth || $elem.scrollHeight != $elem.clientHeight) {
        if (_boundAncestors == null) {
          _boundAncestors = $elem;
        } else {
          try {
            _boundAncestors.append($elem);
          } catch (e) {
            print(e);
          }
        }
        _scrollSubscription.add($elem.onScroll.listen(_handleActiveCellPositionChange));
      }
      if($elem.parentNode is dom.ShadowRoot) {
        $elem = ($elem.parentNode as dom.ShadowRoot).host;
      } else {
        $elem = $elem.parent;
      }
    }
  }

  void _unbindAncestorScrollEvents() {
    if (_boundAncestors == null) {
      return;
    }
    _scrollSubscription.forEach((e) => e.cancel());
    _scrollSubscription.clear();
    //$boundAncestors.unbind("scroll." + uid);
    _boundAncestors = null;
  }

  void updateColumnHeader(String columnId, String title, String toolTip) {
    if (!_initialized) { return; }
    var idx = getColumnIndex(columnId);
    if (idx == null) {
      return;
    }

    Column columnDef = columns[idx];
    dom.HtmlElement $header = _headers.children.firstWhere((e) => e.id == idx); //().eq(idx); // TODO check
    if ($header != null) {
      if (title != null) {
        columns[idx].name = title;
      }
      if (toolTip != null) {
        columns[idx].toolTip = toolTip;
      }

      _eventBus.fire(core.Events.BEFORE_HEADER_CELL_DESTROY, new core.BeforeHeaderCellDestroy(this, $header, columnDef));

      $header
          ..attributes["title"] = toolTip != null ? toolTip : ""
          ..children.where((e) => e.id == 0).forEach((e) => e.innerHtml = title); //().eq(0).html(title); // TODO check

      _eventBus.fire(core.Events.HEADER_CELL_RENDERED, new core.HeaderCellRendered(this, $header, columnDef));
    }
  }

  dom.HtmlElement getHeaderRow() {
    return _headerRow;
  }

  dom.HtmlElement getHeaderRowColumn(columnId) {
    var idx = getColumnIndex(columnId);
    dom.HtmlElement $header = _headerRow.children.firstWhere((e) => e == idx); //.eq(idx); // TODO check
    if($header != null && $header.children.length > 0) {
      return $header;
    }
    return null;
  }

  void _createColumnHeaders() {
    var onMouseEnter = (dom.MouseEvent e) {
      (e.target as dom.HtmlElement).classes.add("ui-state-hover");
    };

    var onMouseLeave = (dom.MouseEvent e) {
      (e.target as dom.HtmlElement).classes.remove("ui-state-hover");
    };

    _headers.querySelectorAll(".bwu-datagrid-header-column")
      .forEach((BwuDatagridHeaderColumn e) { // TODO check self/this
        Column columnDef = e.column;
        if (columnDef != null) {
          _eventBus.fire(core.Events.BEFORE_HEADER_CELL_DESTROY, new core.BeforeHeaderCellDestroy(this, e, columnDef));
        }
      });
    _headers.children.clear();
    _headers.style.width = "${_getHeadersWidth()}px";

    _headerRow.querySelectorAll(".bwu-datagrid-headerrow-column")
      .forEach((BwuDatagridHeaderrowColumn e) { // TODO check self/this
        Column columnDef = e.column;
        if (columnDef != null) {
          _eventBus.fire(core.Events.BEFORE_HEADER_CELL_DESTROY, new core.BeforeHeaderCellDestroy(this, e, columnDef));
        }
      });
    _headerRow.children.clear();

    if(columns != null) {
      for (int i = 0; i < columns.length; i++) {
        Column m = columns[i];

        var header = (new dom.Element.tag('bwu-datagrid-header-column') as BwuDatagridHeaderColumn)
            ..classes.add('ui-state-default')
            ..classes.add('bwu-datagrid-header-column')
            ..append(new dom.SpanElement()..classes.add('bwu-datagrid-column-name')..text = m.name)
            ..style.width = "${m.width - _headerColumnWidthDiff}px"
            //..attributes["id"] ='${uid}${m.id}'
            ..attributes["id"] ='${m.id}'
            ..attributes["title"] = m.toolTip != null ? m.toolTip : ""
            ..column = m
            ..classes.add(m.headerCssClass != null ? m.headerCssClass : "");
        _headers.append(header);

        if (_gridOptions.enableColumnReorder || m.sortable) {
          header
            ..onMouseEnter.listen(onMouseEnter)
            ..onMouseLeave.listen(onMouseLeave);
        }

        if (m.sortable) {
          header.classes.add("bwu-datagrid-header-sortable");
          header.append(new dom.SpanElement()..classes.add('bwu-datagrid-sort-indicator'));
        }

        _eventBus.fire(core.Events.HEADER_CELL_RENDERED, new core.HeaderCellRendered(this, header, m));

        if (_gridOptions.showHeaderRow) {
          var headerRowCell = (new dom.Element.tag('bwu-datagrid-headerrow-column') as BwuDatagridHeaderrowColumn)
              ..classes.add('ui-state-default')
              ..classes.add('bwu-datagrid-headerrow-column')
              ..classes.add('l${i}')
              ..classes.add('r${i}')
              ..column =  m;
              _headerRow.append(headerRowCell);

              _eventBus.fire(core.Events.HEADER_CELL_RENDERED, new core.HeaderCellRendered(this, headerRowCell, m));
        }
      }
    }

    setSortColumns(_sortColumns);
    _setupColumnResize();
    if (_gridOptions.enableColumnReorder) {
      _setupColumnReorder();
    }
  }

  void _setupColumnSort() {
    _headers.onClick.listen((e) {
      // temporary workaround for a bug in jQuery 1.7.1 (http://bugs.jquery.com/ticket/11328)
      // e.metaKey = e.metaKey || e.ctrlKey; // TODO process Ctrl-key

      if ((e.target as dom.HtmlElement).classes.contains("bwu-datagrid-resizable-handle")) {
        return;
      }

      var $col = tools.closest((e.target as dom.HtmlElement), '.bwu-datagrid-header-column') as BwuDatagridHeaderColumn;
      if ($col.children.length > 0) {
        return;
      }

      Column column = $col.column;
      if (column.sortable) {
        if (!getEditorLock.commitCurrentEdit()) {
          return;
        }

        SortColumn sortOpts = null;
        var i = 0;
        for (; i < _sortColumns.length; i++) {
          if (_sortColumns[i].columnId == column.id) {
            sortOpts = _sortColumns[i];
            sortOpts.sortAsc = !sortOpts.sortAsc;
            break;
          }
        }

        if (e.metaKey && _gridOptions.multiColumnSort) {
          if (sortOpts != null) {
            _sortColumns.removeAt(i);
          }
        }
        else {
          if ((!e.shiftKey && !e.metaKey) || !_gridOptions.multiColumnSort) {
            _sortColumns = [];
          }

          if (sortOpts == null) {
            sortOpts = new SortColumn(column.id,column.defaultSortAsc);
            _sortColumns.add(sortOpts);
          } else if (_sortColumns.length == 0) {
            _sortColumns.add(sortOpts);
          }
        }

        setSortColumns(_sortColumns);

        if (!_gridOptions.multiColumnSort) {
          _eventBus.fire(core.Events.SORT, new core.Sort(this, false, column, null, sortOpts.sortAsc, e));
        } else {
          var sortCols = new Map.fromIterable(_sortColumns, key: (k) => columns[getColumnIndex(k.columnId)], value: (k) => k.sortAsc);
          _eventBus.fire(core.Events.SORT, new core.Sort(this, true, null, sortCols, null, e));
        }
      }
    });
  }

  void _setupColumnReorder() {
    _headers.filter = new Filter(":ui-sortable")..sortable.destroy(); //("destroy");
    _headers.sortable = new Sortable(
      containment: 'parent',
      distance: 3,
      axis: 'x',
      cursor: 'default',
      tolerance: 'intersection',
      helper: 'clone',
      placeholder: 'bwu-datagrid-sortable-placeholder ui-state-default bwu-datagrid-header-column',
      start: (e, ui) {
        ui.placeholder.width(tools.outerWidth(ui) - _headerColumnWidthDiff);
        (ui.helper as dom.HtmlElement).classes.add('bwu-datagrid-header-column-active');
      },
      beforeStop: (e, ui) {
        (ui.helper as dom.HtmlElement).classes.remove('bwu-datagrid-header-column-active');
      });
    _headers.sortable.stop =
      (e) {
        if (!getEditorLock.commitCurrentEdit()) {
          _headers.sortable.cancel(); //('cancel'); // TODO
          return;
        }

        var reorderedIds = _headers.sortable.toArray(); //("toArray");
        var reorderedColumns = [];
        for (var i = 0; i < reorderedIds.length; i++) {
          reorderedColumns.add(columns[getColumnIndex(reorderedIds[i].replace(uid, ""))]); // TODO what is uid for here?
        }
        setColumns = reorderedColumns;

        _eventBus.fire(core.Events.COLUMNS_REORDERED, new core.ColumnsReordered(this));
        e.stopPropagation();
        _setupColumnResize();
      };
  }

  void _setupColumnResize() {
    Column c;
    int pageX;
    List<BwuDatagridHeaderColumn> columnElements;
    int minPageX, maxPageX;
    int firstResizable, lastResizable;
    columnElements = new List<BwuDatagridHeaderColumn>.from(_headers.children);
    _headers.querySelectorAll(".bwu-datagrid-resizable-handle").forEach((dom.HtmlElement e) {
      e.remove();
    });
    for(int i = 0; i < columnElements.length; i++) {
      if (columns[i].resizable) {
        if (firstResizable == null) {
          firstResizable = i;
        }
        lastResizable = i;
      }
    }
    if (firstResizable == null) {
      return;
    }
    for(int i = 0; i < columnElements.length; i++) {
      var header_col = columnElements[i];
      if (i < firstResizable || (_gridOptions.forceFitColumns && i >= lastResizable)) {
        return;
      }

      var div = new dom.DivElement()
        ..classes.add('bwu-datagrid-resizable-handle')
        ..draggable = true;
      header_col.append(div);

      div
          ..onDragStart.listen((dom.MouseEvent e) {
            if (!getEditorLock.commitCurrentEdit()) {
              return false;
            }
            pageX = e.page.x;
            (e.target as dom.HtmlElement).parent.classes.add("bwu-datagrid-header-column-active");
            int shrinkLeewayOnRight = null, stretchLeewayOnRight = null;
            // lock each column's width option to current width
            for(int i = 0; i < columnElements.length; i++) {
              columns[i].previousWidth = tools.outerWidth(columnElements[i]);
            }
            if (_gridOptions.forceFitColumns) {
              shrinkLeewayOnRight = 0;
              stretchLeewayOnRight = 0;
              // colums on right affect maxPageX/minPageX
              for (int j = i + 1; j < columnElements.length; j++) {
                c = columns[j];
                if (c.resizable) {
                  if (stretchLeewayOnRight != null) {
                    if (c.maxWidth > 0) {
                      stretchLeewayOnRight += c.maxWidth - c.previousWidth;
                    } else {
                      stretchLeewayOnRight = null;
                    }
                  }
                  shrinkLeewayOnRight += c.previousWidth - math.max(c.minWidth != null ? c.minWidth : 0, _absoluteColumnMinWidth);
                }
              }
            }
            int shrinkLeewayOnLeft = 0, stretchLeewayOnLeft = 0;
            for (int j = 0; j <= i; j++) {
              // columns on left only affect minPageX
              c = columns[j];
              if (c.resizable) {
                if (stretchLeewayOnLeft != null) {
                  if (c.maxWidth != null) {
                    stretchLeewayOnLeft += c.maxWidth - c.previousWidth;
                  } else {
                    stretchLeewayOnLeft = null;
                  }
                }
                shrinkLeewayOnLeft += c.previousWidth - math.max(c.minWidth != null ? c.minWidth : 0, _absoluteColumnMinWidth);
              }
            }
            if (shrinkLeewayOnRight == null) {
              shrinkLeewayOnRight = 100000;
            }
            if (shrinkLeewayOnLeft == null) {
              shrinkLeewayOnLeft = 100000;
            }
            if (stretchLeewayOnRight == null) {
              stretchLeewayOnRight = 100000;
            }
            if (stretchLeewayOnLeft == null) {
              stretchLeewayOnLeft = 100000;
            }
            maxPageX = pageX + math.min(shrinkLeewayOnRight, stretchLeewayOnLeft);
            minPageX = pageX - math.min(shrinkLeewayOnLeft, stretchLeewayOnRight);
          })

          ..onDrag.listen((dom.MouseEvent e) {
            int actualMinWidth;
            if(e.page.x == 0) {
              return;
            }
            int d = math.min(maxPageX, math.max(minPageX, e.page.x)) - pageX;
            int x;
            if (d < 0) { // shrink column
              x = d;
              for (int j = i; j >= 0; j--) {
                c = columns[j];
                if (c.resizable) {
                  actualMinWidth = math.max(c.minWidth != null ? c.minWidth : 0, _absoluteColumnMinWidth);
                  if (x != null && c.previousWidth + x < actualMinWidth) {
                    x += c.previousWidth - actualMinWidth;
                    c.width = actualMinWidth;
                  } else {
                    c.width = c.previousWidth + x;
                    x = 0;
                  }
                }
              }

              if (_gridOptions.forceFitColumns) {
                x = -d;
                for (int j = i + 1; j < columnElements.length; j++) {
                  c = columns[j];
                  if (c.resizable) {
                    if (x && c.maxWidth != null && (c.maxWidth - c.previousWidth < x)) {
                      x -= c.maxWidth - c.previousWidth;
                      c.width = c.maxWidth;
                    } else {
                      c.width = c.previousWidth + x;
                      x = 0;
                    }
                  }
                }
              }
            } else { // stretch column
              x = d;
              for (int j = i; j >= 0; j--) {
                c = columns[j];
                if (c.resizable) {
                  if (x > 0 && c.maxWidth != null && (c.maxWidth - c.previousWidth < x)) {
                    x -= c.maxWidth - c.previousWidth;
                    c.width = c.maxWidth;
                  } else {
                    c.width = c.previousWidth + x;
                    x = 0;
                  }
                }
              }

              if (_gridOptions.forceFitColumns) {
                x = -d;
                for (int j = i + 1; j < columnElements.length; j++) {
                  c = columns[j];
                  if (c.resizable) {
                    actualMinWidth = math.max(c.minWidth != null ? c.minWidth : 0, _absoluteColumnMinWidth);
                    if (x > 0 && c.previousWidth + x < actualMinWidth) {
                      x += c.previousWidth - actualMinWidth;
                      c.width = actualMinWidth;
                    } else {
                      c.width = c.previousWidth + x;
                      x = 0;
                    }
                  }
                }
              }
            }
            _applyColumnHeaderWidths();
            if (_gridOptions.syncColumnCellResize) {
              _applyColumnWidths();
            }
          })

          ..onDragEnd.listen((dom.MouseEvent e) {
            var newWidth;
            (e.target as dom.HtmlElement).parent.classes.remove("bwu-datagrid-header-column-active");
            for (int j = 0; j < columnElements.length; j++) {
              c = columns[j];
              newWidth = tools.outerWidth(columnElements[j]);

              if (c.previousWidth != newWidth && c.rerenderOnResize) {
                invalidateAllRows();
              }
            }
            _updateCanvasWidth(true);
            render();
            _eventBus.fire(core.Events.COLUMNS_RESIZED, new core.ColumnsResized(this));
          });
    }
  }

  int _getVBoxDelta(dom.HtmlElement $el) {
    var p = ["borderTopWidth", "borderBottomWidth", "paddingTop", "paddingBottom"];
    var delta = 0;
    var gcs = $el.getComputedStyle();
    delta += tools.parseInt(gcs.borderTopWidth)
        + tools.parseInt(gcs.borderBottomWidth)
        + tools.parseInt(gcs.paddingTop)
        + tools.parseInt(gcs.paddingBottom);

//    p.forEach((prop) {
//      delta += tools.parseInt($el.style.getPropertyValue(prop)); // || 0; // TODO
//    });
    return delta;
  }

  void _measureCellPaddingAndBorder() {
    var el;
    // changed to direct property access due to https://code.google.com/p/dart/issues/detail?id=18765
//    var h = ["borderLeftWidth", "borderRightWidth", "paddingLeft", "paddingRight"];
//    var v = ["borderTopWidth", "borderBottomWidth", "paddingTop", "paddingBottom"];

    el = (new dom.Element.tag('bwu-datagrid-header-column') as BwuDatagridHeaderColumn)
      ..classes.add('ui-state-default')
      ..classes.add('bwu-datagrid-header-column')
      ..style.visibility = 'hidden';
    _headers.append(el);
    _headerColumnWidthDiff = _headerColumnHeightDiff = 0;
    var gcs = el.getComputedStyle();
    if (el.style.boxSizing != "border-box") {
      //h.forEach((prop) {
        _headerColumnWidthDiff = tools.parseInt(gcs.borderLeftWidth)
        + tools.parseInt(gcs.borderRightWidth)
        + tools.parseInt(gcs.paddingLeft)
        + tools.parseInt(gcs.paddingRight);
             // || 0; // TODO
      //});
      //v.forEach((prop) {
      //  headerColumnHeightDiff += tools.parseInt(gcs.getPropertyValue(prop)); //; || 0; // TODO
      //});
        _headerColumnHeightDiff = tools.parseInt(gcs.borderTopWidth)
            + tools.parseInt(gcs.borderBottomWidth)
            + tools.parseInt(gcs.paddingTop)
            + tools.parseInt(gcs.paddingBottom);
    }
    el.remove();

    var r = new dom.DivElement()..classes.add('bwu-datagrid-row');
    _canvas.append(r);
    el = new dom.DivElement()
      ..id=''
      ..classes.add('bwu-datagrid-cell')
      ..style.visibility='hidden'
      ..appendText('-');

    r.append(el);
    gcs = el.getComputedStyle();
    _cellWidthDiff = _cellHeightDiff = 0;
    if (el.style.boxSizing != "border-box") {
//      h.forEach((prop) {
//        var val = tools.parseInt(el.getComputedStyle().getPropertyValue(prop));
//        cellWidthDiff += val != null ? val : 0; // TODO
//      });
      _cellWidthDiff = tools.parseInt(gcs.borderLeftWidth)
              + tools.parseInt(gcs.borderRightWidth)
              + tools.parseInt(gcs.paddingLeft)
              + tools.parseInt(gcs.paddingRight);
//      v.forEach((prop) {
//        var val = tools.parseInt(el.getComputedStyle().getPropertyValue(prop));
//        cellHeightDiff += val != null ? val : 0; // TODO
//      });
      _cellHeightDiff = tools.parseInt(gcs.borderTopWidth)
          + tools.parseInt(gcs.borderBottomWidth)
          + tools.parseInt(gcs.paddingTop)
          + tools.parseInt(gcs.paddingBottom);

    }
    //var x = r.getComputedStyle();
    r.remove();

    _absoluteColumnMinWidth = math.max(_headerColumnWidthDiff, _cellWidthDiff);
  }

  void _createCssRules() {
    _style = new dom.StyleElement();//.html("<style type='text/css' rel='stylesheet' />", validator: nodeValidator);
    //dom.document.head.append($style);
    this.shadowRoot.append(_style);
    var rowHeight = (_gridOptions.rowHeight - _cellHeightDiff);
    var rules = [
      ".bwu-datagrid-header-column { left: 1000px; }",
      ".bwu-datagrid-top-panel { height:${_gridOptions.topPanelHeight}px; }",
      ".bwu-datagrid-headerrow-columns { height:${_gridOptions.headerRowHeight}px; }",
      ".bwu-datagrid-cell { height:${rowHeight}px; }",
      ".bwu-datagrid-row { height:${_gridOptions.rowHeight}px; }"
    ];

    if(columns != null) {
      for (int i = 0; i < columns.length; i++) {
        rules.add(".l${i} { }");
        rules.add(".r${i} { }");
      }
    }

//    for(int i = 0; i < rules.length; i++) {
//      ($style.sheet as dom.CssStyleSheet).insertRule(rules[i], i);
//    }
    _style.appendText(rules.join(" "));
  }

  // TODO keep the rules in a collection to avoid parsing them
  Map<String,dom.CssStyleRule> _getColumnCssRules(int idx) {
    if (_stylesheet == null) {
//      var sheets = this.shadowRoot.styleSheets;
//      for (int i = 0; i < sheets.length; i++) {
//        if (sheets[i].ownerNode != null && sheets[i].ownerNode == $style) {
//          stylesheet = sheets[i];
//          break;
//        }
//      }
//
//      if (stylesheet == null) {
//        throw "Cannot find stylesheet.";
//      }

      _stylesheet = _style.sheet;

      // find and cache column CSS rules
      _columnCssRulesL = {};
      _columnCssRulesR = {};
      var cssRules = _stylesheet.cssRules;
      Match matches;
      int columnIdx;
      for (var i = 0; i < cssRules.length; i++) {
        var selector = cssRules[i].selectorText;
        matches = new RegExp(r'(?:\.l)(\d+)').firstMatch(selector);
        if (matches != null) {
          columnIdx = tools.parseInt(matches.group(1)); // first.substr(2, matches.first.length - 2));
          _columnCssRulesL[columnIdx] = cssRules[i];
        } else {
          matches = new RegExp(r'(?:\.r)(\d+)').firstMatch(selector);
          if (matches != null) {
            columnIdx = tools.parseInt(matches.group(1)); //first.substr(2, matches.first.length - 2));
            _columnCssRulesR[columnIdx] = cssRules[i];
          }
        }
      }
    }

    return {
      "left": _columnCssRulesL[idx],
      "right": _columnCssRulesR[idx]
    };
  }

  void _removeCssRules() {
    _style.remove();
    _stylesheet = null;
  }

  void destroy() {
    getEditorLock.cancelCurrentEdit();

    _eventBus.fire(core.Events.BEFORE_DESTROY, new core.BeforeDestroy(this));

    var i = _plugins.length;
    while(i--) {
      unregisterPlugin(_plugins[i]);
    }

    if (_gridOptions.enableColumnReorder) {
        _headers.filter = new Filter(":ui-sortable")..sortable.destroy(); //("destroy"); // TODO
    }

    _unbindAncestorScrollEvents();
    // $container.unbind(".bwu-datagrid"); // TODO
    _removeCssRules();

    // $canvas.unbind("draginit dragstart dragend drag"); // TODO
    //$container
    //    ..children.clear();
    //this.classes.remove(uid);
  }


  //////////////////////////////////////////////////////////////////////////////////////////////
  // General

//  function trigger(evt, args, e) {
//    e = e || new EventData();
//    args = args || {};
//    args.grid = self;
//    return evt.notify(args, e, self);
//  }

  // TODO IEditor interface
  core.EditorLock get getEditorLock => _gridOptions.editorLock;

  // TODO IEditor interface
  EditController get getEditController => _editController;

  int getColumnIndex(id) => _columnsById[id];

  void autosizeColumns() {
    int i;
    Column c;
    List<int> widths = [];
    int shrinkLeeway = 0;
    int total = 0;
    int prevTotal;
    int availWidth = _viewportHasVScroll ? _viewportW - scrollbarDimensions.x : _viewportW;

    for (i = 0; i < columns.length; i++) {
      c = columns[i];
      widths.add(c.width);
      total += c.width;
      if (c.resizable) {
        shrinkLeeway += c.width - math.max(c.minWidth, _absoluteColumnMinWidth);
      }
    }

    // shrink
    prevTotal = total;
    while (total > availWidth && shrinkLeeway) {
      double shrinkProportion = (total - availWidth) / shrinkLeeway;
      for (i = 0; i < columns.length && total > availWidth; i++) {
        c = columns[i];
        var width = widths[i];
        if (!c.resizable || width <= c.minWidth || width <= _absoluteColumnMinWidth) {
          continue;
        }
        var absMinWidth = math.max(c.minWidth, _absoluteColumnMinWidth);
        var shrinkSize = (shrinkProportion * (width - absMinWidth)).floor();
        if(shrinkSize == 0) {
          shrinkSize = 1;
        }
        shrinkSize = math.min(shrinkSize, width - absMinWidth);
        total -= shrinkSize;
        shrinkLeeway -= shrinkSize;
        widths[i] -= shrinkSize;
      }
      if (prevTotal <= total) {  // avoid infinite loop
        break;
      }
      prevTotal = total;
    }

    // grow
    prevTotal = total;
    while (total < availWidth) {
      var growProportion = availWidth / total;
      for (i = 0; i < columns.length && total < availWidth; i++) {
        c = columns[i];
        var currentWidth = widths[i];
        var growSize;

        if (!c.resizable || c.maxWidth <= currentWidth) {
          growSize = 0;
        } else {
          var tmp = (c.maxWidth - currentWidth > 0 ? c.maxWidth - currentWidth : 1000000);
          growSize = math.min((growProportion * currentWidth).floor() - currentWidth, tmp);
          if(growSize == 0) {
            growSize = 1;
          }
        }
        total += growSize;
        widths[i] += growSize;
      }
      if (prevTotal >= total) {  // avoid infinite loop
        break;
      }
      prevTotal = total;
    }

    var reRender = false;
    for (i = 0; i < columns.length; i++) {
      if (columns[i].rerenderOnResize && columns[i].width != widths[i]) {
        reRender = true;
      }
      columns[i].width = widths[i];
    }

    _applyColumnHeaderWidths();
    _updateCanvasWidth(true);
    if (reRender) {
      invalidateAllRows();
      render();
    }
  }

  void _applyColumnHeaderWidths() {
    if (!_initialized) { return; }
    var h;
    for (int i = 0; i < _headers.children.length; i++) {
      h = _headers.children[i];
      if (h.style.width != columns[i].width - _headerColumnWidthDiff) { // TODO comparsion
        h.style.width = '${columns[i].width - _headerColumnWidthDiff}px';
      }
    }

    _updateColumnCaches();
  }

  void _applyColumnWidths() {
    int x = 0;
    int w;
    Map<String,dom.CssStyleRule> rule;
    if(columns != null) {
      for (var i = 0; i < columns.length; i++) {
        w = columns[i].width;

        rule = _getColumnCssRules(i);
        rule['left'].style.left = '${x}px';
        rule['right'].style.right = '${(_canvasWidth - x - w)}px';

        x += columns[i].width;
      }
    }

//    String s = '';
//    stylesheet.rules.forEach((e) => s += "${e.cssText} ");
//    print(s);
//    $style.text = s;

   // $style.text = stylesheet.rules.join(' '); // TODO does this what it is intended for?
  }

  void setSortColumn(String columnId, bool ascending) {
    setSortColumns([new SortColumn(columnId, ascending)]);
  }

  void setSortColumns(List<SortColumn> cols) {
    _sortColumns = cols;

    List<BwuDatagridHeaderColumn> headerColumnEls = new List<BwuDatagridHeaderColumn>.from(_headers.children);
    headerColumnEls.forEach((hc) {
        hc..classes.remove("bwu-datagrid-header-column-sorted")
        ..querySelectorAll(".bwu-datagrid-sort-indicator").forEach((dom.HtmlElement e) =>
            e.classes
            ..remove('bwu-datagrid-sort-indicator-asc')
            ..remove('bwu-datagrid-sort-indicator-desc'));
    });

    _sortColumns.forEach((col) {
      if (col.sortAsc == null) {
        col.sortAsc = true;
      }
      var columnIndex = getColumnIndex(col.columnId);
      if (columnIndex != null) {
        headerColumnEls[columnIndex] // TODO verify
            ..classes.add("bwu-datagrid-header-column-sorted")
            ..querySelector(".bwu-datagrid-sort-indicator")
                .classes.add(col.sortAsc ? "bwu-datagrid-sort-indicator-asc" : "bwu-datagrid-sort-indicator-desc");
      }
    });
  }

  List<SortColumn> get getSortColumns => _sortColumns;

  void _selectedRangesChangedHandler(dom.CustomEvent e, [List<Range> ranges]) {
    _selectedRows = [];
    List<Map<String,String>> hash = [];
    for (var i = 0; i < ranges.length; i++) {
      for (var j = ranges[i].fromRow; j <= ranges[i].toRow; j++) {
        if (hash[j] == null) {  // prevent duplicates
          _selectedRows.add(j);
          hash[j] = {};
        }
        for (var k = ranges[i].fromCell; k <= ranges[i].toCell; k++) {
          if (canCellBeSelected(j, k)) {
            hash[j][columns[k].id] = _gridOptions.selectedCellCssClass;
          }
        }
      }
    }

    setCellCssStyles(_gridOptions.selectedCellCssClass, hash);

    _eventBus.fire(core.Events.SELECTED_ROWS_CHANGED, new core.SelectedRowsChanged(this, getSelectedRows, e));
  }

  List<Column> get getColumns => columns;

  void _updateColumnCaches() {
    // Pre-calculate cell boundaries.
    _columnPosLeft = new List(columns != null ? columns.length : 0);
    _columnPosRight = new List(columns != null ? columns.length : 0);
    var x = 0;
    if(columns != null) {
      for (var i = 0; i < columns.length; i++) {
        _columnPosLeft[i] = x;
        _columnPosRight[i] = x + columns[i].width;
        x += columns[i].width;
      }
    }
  }

  void set setColumns(List<Column> columnDefinitions) {
    _columns = columnDefinitions;

    _columnsById = {};
    for (var i = 0; i < columns.length; i++) {
      Column m = columns[i] = new Column()..extend(columnDefinitions[i])..extend(columns[i]);
      _columnsById[m.id] = i;
      if (m.minWidth != null && (m.width == null || m.width < m.minWidth)) {
        m.width = m.minWidth;
      }
      if (m.maxWidth != null && m.width != null && m.width > m.maxWidth) {
        m.width = m.maxWidth;
      }
    }

    _updateColumnCaches();

    if (_initialized) {
      invalidateAllRows();
      _createColumnHeaders();
      _removeCssRules();
      _createCssRules();
      resizeCanvas();
      _applyColumnWidths();

      this.shadowRoot.append(_style);
      _handleScroll();
    }
  }

  GridOptions get getGridOptions => _gridOptions;

  void set setGridOptions(GridOptions newGridOptions) {
    if (!getEditorLock.commitCurrentEdit()) {
      return;
    }

    _makeActiveCellNormal();

    if (_gridOptions.enableAddRow != newGridOptions.enableAddRow) {
      invalidateRow(getDataLength);
    }

    _gridOptions.extend(newGridOptions); // TODO verify
    _validateAndEnforceOptions();

    _viewport.style.overflowY = _gridOptions.autoHeight ? "hidden" : "auto";
    render();
  }

  void _validateAndEnforceOptions() {
    if (_gridOptions.autoHeight) {
      _gridOptions.leaveSpaceForNewRows = false;
    }
  }

  void setDataView(DataView newData, [bool scrollToTop = false]) {
    _dataView = newData;
    _dataMap = null;
    _setData(scrollToTop);
  }

  void setDataMap(List<Map> newData, [bool scrollToTop = false]) {
    _dataMap = newData;
    _dataView = null;
  }

  void _setData(bool scrollToTop) {
    invalidateAllRows();
    updateRowCount();
    if (scrollToTop) {
      _scrollTo(0);
    }
  }

  int get getDataLength {
    if (_dataMap != null) {
      return _dataMap.length;
    } else if(dataView != null){
      return dataView.getLength;
    } else {
      return 0;
    }
  }

  int _getDataLengthIncludingAddNew() {
    return getDataLength + (_gridOptions.enableAddRow ? 1 : 0);
  }

  Map getDataMapItem(int i) {
    if(i >= _dataMap.length) {
      return null;
    }
    return _dataMap[i];
  }

  Item getDataViewItem(int i) => dataView.items[i];

  dom.HtmlElement get getTopPanel => _topPanel;

  void set setTopPanelVisibility(visible) {
    if (_gridOptions.showTopPanel != visible) {
      _gridOptions.showTopPanel = visible;
      if (visible) {
        _topPanelScroller.slideDown("fast", resizeCanvas);
      } else {
        _topPanelScroller.slideUp("fast", resizeCanvas);
      }
    }
  }

  void set setHeaderRowVisibility(bool visible) {
    if (_gridOptions.showHeaderRow != visible) {
      _gridOptions.showHeaderRow = visible;
      if (visible) {
        _headerRowScroller.slideDown("fast", resizeCanvas);
      } else {
        _headerRowScroller.slideUp("fast", resizeCanvas);
      }
    }
  }

  dom.ShadowRoot get getContainerNode => _container;

  //////////////////////////////////////////////////////////////////////////////////////////////
  // Rendering / Scrolling

  int _getRowTop(int row) {
    var x = _gridOptions.rowHeight * row - pageOffset;
    //print('rowTop - row: ${row}: ${x}');
    return x;
  }

  int _getRowFromPosition(int y) {
    return ((y + pageOffset) / _gridOptions.rowHeight).floor();
  }

  void _scrollTo(int y) {
    y = math.max(y, 0);
    y = math.min(y, th - _viewportH + (_viewportHasHScroll ? scrollbarDimensions.y : 0));

    var oldOffset = pageOffset;

    page = math.min(n - 1, (y / ph).floor());
    pageOffset = (page * cj).round();
    int newScrollTop = y - pageOffset;

    if (pageOffset != oldOffset) {
      var range = _getVisibleRange(newScrollTop);
      _cleanupRows(range);
      _updateRowPositions();
    }

    if (_prevScrollTop != newScrollTop) {
      vScrollDir = (_prevScrollTop + oldOffset < newScrollTop + pageOffset) ? 1 : -1;
      _viewport.scrollTop = (_lastRenderedScrollTop = _scrollTop = _prevScrollTop = newScrollTop);

      _eventBus.fire(core.Events.VIEWPORT_CHANGED, new core.ViewportChanged(this));
    }
  }

  Formatter _getFormatter(int row, Column column) {
    var rowMetadata = dataView != null && dataView.getItemMetadata != null ? dataView.getItemMetadata(row) : null;

    // look up by id, then index
    var columnOverrides = rowMetadata != null ?
        (rowMetadata.columns[column.id] != null ? rowMetadata.columns[column.id] : rowMetadata.columns[getColumnIndex(column.id)]) : null;

    var result = (columnOverrides != null && columnOverrides.formatter != null) ? columnOverrides.formatter :
        (rowMetadata != null && rowMetadata.formatter != null ? rowMetadata.formatter :
        column.formatter); // TODO check
    if(result == null) {
      if(_gridOptions.formatterFactory != null) {
        result = _gridOptions.formatterFactory.getFormatter(column);
      }
    }
    if(result == null) {
        result = _gridOptions.defaultFormatter;
    }
    return result;
  }

  Editor _getEditor(int row, int cell) {
    var column = columns[cell];
    var rowMetadata = dataView != null && dataView.getItemMetadata != null ? dataView.getItemMetadata(row) : null;
    var columnMetadata = rowMetadata != null ? rowMetadata.columns : null;

    if (columnMetadata != null && columnMetadata[column.id] != null && columnMetadata[column.id].editor != null) {
      return columnMetadata[column.id].editor;
    }
    if (columnMetadata != null && columnMetadata[cell] != null && columnMetadata[cell].editor != null) {
      return columnMetadata[cell].editor;
    }

    return column.editor != null ? column.editor : (_gridOptions.editorFactory != null ? _gridOptions.editorFactory.getEditor(column): null);
  }

  dynamic _getDataItemValueForColumn(/*Item/Map*/ item, Column columnDef) {
    if (_gridOptions.dataItemColumnValueExtractor != null) {
      return _gridOptions.dataItemColumnValueExtractor(item, columnDef);
    }
    return item[columnDef.field];
  }

  dom.HtmlElement _appendRowHtml(/*dom.HtmlElement stringArray,*/ int row, Range range, int dataLength) {
    var d = getDataMapItem(row);
    var dataLoading = row < dataLength && d == null;
    var rowCss = 'bwu-datagrid-row ${dataLoading ? " loading" : ""} ${row == _activeRow ? " active" : ""} ${row % 2 == 1 ? " odd" : " even"}';

    if (d == null) {
      "${rowCss} ${_gridOptions.addNewRowCssClass}";
    }

    ItemMetadata metadata = dataView != null && dataView.getItemMetadata != null ? dataView.getItemMetadata(row) : null;

    if (metadata != null && metadata.cssClasses != null) {
      "${rowCss} ${metadata.cssClasses}";
    }

    dom.HtmlElement rowElement =

        new dom.DivElement()
          ..classes.add('ui-widget-content')
          ..classes.add(rowCss)
          ..style.top = '${_getRowTop(row)}px';
    //stringArray.add(rowElement);

    String colspan;
    Column m;
    if(columns != null) {
      for (var i = 0, ii = columns.length; i < ii; i++) {
        m = columns[i];
        colspan = '1';
        if (metadata != null && metadata.columns != null) {
          var columnData = metadata.columns[m.id] != null ? metadata.columns[m.id] : metadata.columns[i];
          colspan = columnData != null && columnData.colspan != null ? columnData.colspan : '1';
          if (colspan == "*") {
            colspan = '${ii - i}';
          }
        }

        // Do not render cells outside of the viewport.
        if (_columnPosRight[math.min(ii - 1, i + tools.parseInt(colspan) - 1)] > range.leftPx) {
          if (_columnPosLeft[i] > range.rightPx) {
            // All columns to the right are outside the range.
            break;
          }

          _appendCellHtml(rowElement, row, i, colspan, d);
        }

        int intColspan = tools.parseInt(colspan);
        if (intColspan > 1) {
          i += (intColspan - 1);
        }
      }
    }

    //stringArray.add("</div>");
    return rowElement;
  }

  void _appendCellHtml(dom.HtmlElement rowElement, int row, int cell, String colspan, /*Item/Map*/ item) {
    assert(item is Item || item is Map || item == null);

    var m = columns[cell];
    var cellCss = "bwu-datagrid-cell l${cell} r${math.min(columns.length - 1, cell + tools.parseInt(colspan) - 1)} ${
      (m.cssClass != null ? m.cssClass : '')}";
    if (row == _activeRow && cell == _activeCell) {
      cellCss = "${cellCss} active";
    }

    // TODO:  merge them together in the setter
    for (var key in _cellCssClasses.keys) {
      if (_cellCssClasses[key][row] && _cellCssClasses[key][row][m.id]) {
        cellCss += (" " + _cellCssClasses[key][row][m.id]);
      }
    }

    dom.HtmlElement cellElement = new dom.DivElement()..classes.add(cellCss);
    rowElement.append(cellElement);

    // if there is a corresponding row (if not, this is the Add New row or this data hasn't been loaded yet)
    if (item != null) {
      var value = _getDataItemValueForColumn(item, m);
      /*cellElement.append(new dom.Text(*/_getFormatter(row, m)(cellElement, row, cell, value, m, item); //));
    }

    //stringArray.add("</div>");

    _rowsCache[row].cellRenderQueue.add(cell);
    _rowsCache[row].cellColSpans[cell] = colspan;
  }

  void _cleanupRows(Range rangeToKeep) {
    for (var i = 0; i < _rowsCache.length; i++) { // TODO was probably associative
      if ((i != _activeRow) && (i < rangeToKeep.top || i > rangeToKeep.bottom)) {
        _removeRowFromCache(i);
      }
    }
  }

  void invalidate() {
    updateRowCount();
    invalidateAllRows();
    render();
  }

  void invalidateAllRows() {
    if (_currentEditor != null) {
      _makeActiveCellNormal();
    }
    for (var i = 0; i < _rowsCache.length; i++) { // TODO was probably an associative array
      _removeRowFromCache(i);
    }
  }

  void _removeRowFromCache(int row) {
    var cacheEntry = _rowsCache[row];
    if (cacheEntry == null) {
      return;
    }

    if (_rowNodeFromLastMouseWheelEvent == cacheEntry.rowNode) {
      cacheEntry.rowNode.style.display = 'none';
      _zombieRowNodeFromLastMouseWheelEvent = _rowNodeFromLastMouseWheelEvent;
    } else {
      //$canvas.children[0].remove(cacheEntry.rowNode);
      cacheEntry.rowNode.remove(); // TODO remove/add event handlers
    }

    _rowsCache.remove(row);
    _postProcessedRows.remove(row);
    _renderedRows--;
    _counter_rows_removed++;
  }

  void invalidateRows(List<int> rows) {
    var i, rl;
    if (rows == null || rows.length == 0) {
      return;
    }
    vScrollDir = 0;
    for (i = 0; i < rows.length; i++) {
      if (_currentEditor != null && _activeRow == rows[i]) {
        _makeActiveCellNormal();
      }
      if (_rowsCache[rows[i]] != null) {
        _removeRowFromCache(rows[i]);
      }
    }
  }

  void invalidateRow(int row) {
    invalidateRows([row]);
  }

  void updateCell(int row, int cell) {
    var cellNode = getCellNode(row, cell);
    if (cellNode == null) {
      return;
    }

    var m = columns[cell], d = getDataMapItem(row);
    if (_currentEditor && _activeRow == row && _activeCell == cell) {
      _currentEditor.loadValue(d);
    } else {
      cellNode.innerHtml = d ? _getFormatter(row, m)(row, cell, _getDataItemValueForColumn(d, m), m, d) : "";
      _invalidatePostProcessingResults(row);
    }
  }

  void updateRow(int row) {
    var cacheEntry = _rowsCache[row];
    if (cacheEntry == null) {
      return;
    }

    _ensureCellNodesInRowsCache(row);

    var d = getDataMapItem(row);

    for (var columnIdx in cacheEntry.cellNodesByColumnIdx.keys) {
      if (!cacheEntry.cellNodesByColumnIdx.containsKey(columnIdx)) {
        continue;
      }

      columnIdx = columnIdx | 0;
      var m = columns[columnIdx],
          node = cacheEntry.cellNodesByColumnIdx[columnIdx];

      if (row == _activeRow && columnIdx == _activeCell && _currentEditor != null) {
        _currentEditor.loadValue(d);
      } else if (d != null) {
        /*node.innerHtml =*/ _getFormatter(row, m)(node, row, columnIdx, _getDataItemValueForColumn(d, m), m, d);
      } else {
        node.innerHtml = "";
      }
    }

    _invalidatePostProcessingResults(row);
  }

  int _getViewportHeight() {
    var containerCs = _container.host.getComputedStyle();
    var headerScrollerCs = _headerScroller.getComputedStyle();

    var x =
     tools.parseInt(containerCs.height) -
        tools.parseInt(containerCs.paddingTop) -
        tools.parseInt(containerCs.paddingBottom) -
        tools.parseInt(headerScrollerCs.height) - _getVBoxDelta(_headerScroller) -
        (_gridOptions.showTopPanel ? _gridOptions.topPanelHeight + _getVBoxDelta(_topPanelScroller) : 0) -
        (_gridOptions.showHeaderRow ? _gridOptions.headerRowHeight + _getVBoxDelta(_headerRowScroller) : 0);
    //print('viewportHeight: ${x}');
    return x;
  }

  void resizeCanvas([int e]) {
    if (!_initialized) { return; }
    if (_gridOptions.autoHeight) {
      _viewportH = _gridOptions.rowHeight * _getDataLengthIncludingAddNew();
    } else {
      _viewportH = _getViewportHeight();
    }

    _numVisibleRows = (_viewportH / _gridOptions.rowHeight).ceil();
    _viewportW = this.offsetWidth; //tools.parseInt(this.getComputedStyle().width);
    if (!_gridOptions.autoHeight) {
      _viewport.style.height = "${_viewportH}px";
    }

    if (_gridOptions.forceFitColumns) {
      autosizeColumns();
    }

    updateRowCount();
    _handleScroll();
    // Since the width has changed, force the render() to reevaluate virtually rendered cells.
    _lastRenderedScrollLeft = -1;
    render();
  }

  void updateRowCount() {
    if (!_initialized) { return; }

    var dataLengthIncludingAddNew = _getDataLengthIncludingAddNew();
    var numberOfRows = dataLengthIncludingAddNew +
        (_gridOptions.leaveSpaceForNewRows ? _numVisibleRows - 1 : 0);

    var oldViewportHasVScroll = _viewportHasVScroll;
    // with autoHeight, we do not need to accommodate the vertical scroll bar
    _viewportHasVScroll = !_gridOptions.autoHeight && (numberOfRows * _gridOptions.rowHeight > _viewportH);

    _makeActiveCellNormal();

    // remove the rows that are now outside of the data range
    // this helps avoid redundant calls to .removeRow() when the size of the data decreased by thousands of rows
    var l = dataLengthIncludingAddNew - 1;

    for (int i = 0; i < _rowsCache.length; i++) {
      if (i >= l) {
        _removeRowFromCache(i);
      }
    }

    if (_activeCellNode != null && _activeRow > l) {
      resetActiveCell();
    }

    var oldH = h;
    th = math.max(_gridOptions.rowHeight * numberOfRows, _viewportH - scrollbarDimensions.y);
    if (th < maxSupportedCssHeight) {
      // just one page
      h = ph = th.toDouble();
      n = 1;
      cj = 0.0;
    } else {
      // break into pages
      h = maxSupportedCssHeight.toDouble();
      ph = h / 100;
      n = (th / ph).floor();
      cj = (th - h) / (n - 1);
    }

    if (h != oldH) {
      _canvas.style.height = "${h}px";
      _scrollTop = _viewport.scrollTop;
    }

    var oldScrollTopInRange = (_scrollTop + pageOffset <= th - _viewportH);

    if (th == 0 || _scrollTop == 0) {
      page = pageOffset = 0;
    } else if (oldScrollTopInRange) {
      // maintain virtual position
      _scrollTo(_scrollTop + pageOffset);
    } else {
      // scroll to bottom
      _scrollTo((th - _viewportH).round());
    }

    if (h != oldH && _gridOptions.autoHeight) {
      resizeCanvas();
    }

    if (_gridOptions.forceFitColumns && oldViewportHasVScroll != _viewportHasVScroll) {
      autosizeColumns();
    }
    _updateCanvasWidth(false);
  }

  Range getViewport([int viewportTop, int viewportLeft]) => _getVisibleRange(viewportTop, viewportLeft);

  Range _getVisibleRange([int viewportTop, int viewportLeft]) {
    if (viewportTop == null) {
      viewportTop = _scrollTop;
    }
    if (viewportLeft == null) {
      viewportLeft = scrollLeft;
    }

    return new Range(
      top: _getRowFromPosition(viewportTop),
      bottom: _getRowFromPosition(viewportTop + _viewportH) + 1,
      leftPx: viewportLeft,
      rightPx: viewportLeft + _viewportW
    );
  }

  Range getRenderedRange([int viewportTop, int viewportLeft]) {
    var range = _getVisibleRange(viewportTop, viewportLeft);
    int buffer = (_viewportH / _gridOptions.rowHeight).round();
    int minBuffer = 3;

    if (vScrollDir == -1) {
      range.top -= buffer;
      range.bottom += minBuffer;
    } else if (vScrollDir == 1) {
      range.top -= minBuffer;
      range.bottom += buffer;
    } else {
      range.top -= minBuffer;
      range.bottom += minBuffer;
    }

    range.top = math.max(0, range.top);
    range.bottom = math.min(_getDataLengthIncludingAddNew() - 1, range.bottom);

    range.leftPx -= _viewportW;
    range.rightPx += _viewportW;

    range.leftPx = math.max(0, range.leftPx);
    range.rightPx = math.min(_canvasWidth, range.rightPx);

    return range;
  }

  void _ensureCellNodesInRowsCache(int row) {
    var cacheEntry = _rowsCache[row];
    if (cacheEntry != null) {
      if (cacheEntry.cellRenderQueue.length > 0) {
        var lastChild = cacheEntry.rowNode.lastChild;
        while (cacheEntry.cellRenderQueue.length > 0) {
          var columnIdx = cacheEntry.cellRenderQueue.removeLast(); // TODO check if removefirst is the right replacement for pop()
          cacheEntry.cellNodesByColumnIdx[columnIdx] = lastChild;
          lastChild = lastChild.previousNode;
        }
      }
    }
  }

  void _cleanUpCells(Range range, int row) {
    var totalCellsRemoved = 0;
    var cacheEntry = _rowsCache[row];

    // Remove cells outside the range.
    var cellsToRemove = [];
    for (var i in cacheEntry.cellNodesByColumnIdx.keys) {
      // I really hate it when people mess with Array.prototype.
//      if (!cacheEntry.cellNodesByColumnIdx.containsKey(i)) { // TODO check
//        continue;
//      }

      // This is a string, so it needs to be cast back to a number.
      //i = i | 0;

      var colspan = cacheEntry.cellColSpans[i];
      int intColspan = tools.parseInt(colspan);
      if (_columnPosLeft[i] > range.rightPx ||
        _columnPosRight[math.min(columns.length - 1, i + intColspan - 1)] < range.leftPx) {
        if (!(row == _activeRow && i == _activeCell)) {
          cellsToRemove.add(i);
        }
      }
    }

    int cellToRemove;
    while (cellsToRemove.length > 0) {
      cellToRemove = cellsToRemove.removeLast();
      cacheEntry.cellNodesByColumnIdx[cellToRemove].remove();
      cacheEntry.cellColSpans.remove(cellToRemove);
      cacheEntry.cellNodesByColumnIdx.remove(cellToRemove);
      if (_postProcessedRows.contains(row)) {
        _postProcessedRows[row].remove(cellToRemove);
      }
      totalCellsRemoved++;
    }
  }

  void _cleanUpAndRenderCells(Range range) {
    RowCache cacheEntry;
    //var stringArray = [];
    dom.HtmlElement rowElement = new dom.DivElement();
    var processedRows = [];
    int cellsAdded;
    var totalCellsAdded = 0;
    String colspan;

    for (var row = range.top; row <= range.bottom; row++) {
      cacheEntry = _rowsCache[row];
      if (cacheEntry == null) {
        continue;
      }

      // cellRenderQueue populated in renderRows() needs to be cleared first
      _ensureCellNodesInRowsCache(row);

      _cleanUpCells(range, row);

      // Render missing cells.
      cellsAdded = 0;

      ItemMetadata itemMetadata;
      if(dataView != null) {
        itemMetadata = dataView.getItemMetadata(row);
      }
      List<ColumnMetadata>metadata = itemMetadata != null ? itemMetadata.columns : null;

      var d = getDataMapItem(row);

      // TODO:  shorten this loop (index? heuristics? binary search?)
      for (var i = 0, ii = columns.length; i < ii; i++) {
        // Cells to the right are outside the range.
        if (_columnPosLeft[i] > range.rightPx) {
          break;
        }

        int intColspan;
        // Already rendered.
        if ((colspan = cacheEntry.cellColSpans[i]) != null) {
          intColspan = tools.parseInt(colspan);
          i += (intColspan > 1 ? intColspan - 1 : 0);
          continue;
        }

        colspan = '1';
        if (metadata != null) {
          var columnData = metadata[columns[i].id] != null ? metadata[columns[i].id] : metadata[i];
          colspan = (columnData != null && columnData.colspan != null) ? columnData.colspan : '1';
          if (colspan == "*") {
            colspan = '${ii - i}';
          }
        }

        intColspan = tools.parseInt(colspan);
        if (_columnPosRight[math.min(ii - 1, i + intColspan - 1)] > range.leftPx) {
          _appendCellHtml(rowElement, row, i, colspan, d);
          cellsAdded++;
        }

        i += (intColspan > 1 ? intColspan - 1 : 0);
      }

      if (cellsAdded > 0) {
        totalCellsAdded += cellsAdded;
        processedRows.add(row);
      }
    }

    if (rowElement.children.length == 0) {
      return;
    }

    var x = new dom.DivElement();
    rowElement.children.forEach((e) {
      x.append(e.clone(true));
    });

    var processedRow;
    var node;
    while (processedRows.length > 0 && (processedRow = processedRows.removeLast()) != null) {
      cacheEntry = _rowsCache[processedRow];
      var columnIdx;
      while (cacheEntry.cellRenderQueue.length > 0) {
        columnIdx = cacheEntry.cellRenderQueue.removeLast();
        node = x.lastChild;
        cacheEntry.rowNode.append(node);
        cacheEntry.cellNodesByColumnIdx[columnIdx] = node;
      }
    }
  }

  void _renderRows(Range range) {
    var parentNode = _canvas;

    //stringArray = [],
    //dom.HtmlElement rowElement;
    List<dom.HtmlElement> rowElements = [];

    List<int> rows = [];
    bool needToReselectCell = false;
    int dataLength = getDataLength;

    var x = new dom.DivElement();

    for (var i = range.top; i <= range.bottom; i++) {
      if (_rowsCache[i] != null) {
        continue;
      }
      _renderedRows++;
      rows.add(i);

      // Create an entry right away so that appendRowHtml() can
      // start populatating it.
      _rowsCache[i] = new RowCache();
//        rowNode: null,
//
//        // ColSpans of rendered cells (by column idx).
//        // Can also be used for checking whether a cell has been rendered.
//        cellColSpans: [],
//
//        // Cell nodes (by column idx).  Lazy-populated by ensureCellNodesInRowsCache().
//        cellNodesByColumnIdx: [],
//
//        // Column indices of cell nodes that have been rendered, but not yet indexed in
//        // cellNodesByColumnIdx.  These are in the same order as cell nodes added at the
//        // end of the row.
//        cellRenderQueue: []
//      );

      x.append(_appendRowHtml(/*stringArray,*/ i, range, dataLength));
      if (_activeCellNode != null && _activeRow == i) {
        needToReselectCell = true;
      }
      _counter_rows_rendered++;
    }

    if (rows.length == 0) { return; }

    //x.append(rowElement); //stringArray.join(""), validator: nodeValidator);

    for (var i = 0; i < rows.length; i++) {
      _rowsCache[rows[i]].rowNode = parentNode.append(x.firstChild);
      _rowsCache[rows[i]].rowNode.querySelectorAll(".bwu-datagrid-cell").forEach((e) {
        (e as dom.HtmlElement)
          ..onMouseEnter.listen(_handleMouseEnter)
          ..onMouseLeave.listen(_handleMouseLeave);
      });
    }

    if (needToReselectCell) {
      _activeCellNode = getCellNode(_activeRow, _activeCell);
    }
  }

  void _startPostProcessing() {
    if (!_gridOptions.enableAsyncPostRender) {
      return;
    }
    if(_h_postrender != null) {
      _h_postrender.cancel() ;
      _h_postrender = null;
    }
    _h_postrender = new async.Timer(_gridOptions.asyncPostRenderDelay, _asyncPostProcessRows);
  }

  void _invalidatePostProcessingResults(int row) {
    _postProcessedRows.remove(row);
    _postProcessFromRow = math.min(_postProcessFromRow, row);
    _postProcessToRow = math.max(_postProcessToRow, row);
    _startPostProcessing();
  }

  void _updateRowPositions() {
    for (final int row in _rowsCache) {
      _rowsCache[row].rowNode.style.top = "${_getRowTop(row)}px";
    }
  }

  void render() {
    if (!_initialized) { return; }
    var visible = _getVisibleRange();
    var rendered = getRenderedRange();

    // remove rows no longer in the viewport
    _cleanupRows(rendered);

    // add new rows & missing cells in existing rows
    if (_lastRenderedScrollLeft != scrollLeft) {
      _cleanUpAndRenderCells(rendered);
    }

    // render missing rows
    _renderRows(rendered);

    _postProcessFromRow = visible.top;
    _postProcessToRow = math.min(_getDataLengthIncludingAddNew() - 1, visible.bottom);
    _startPostProcessing();

    _lastRenderedScrollTop = _scrollTop;
    _lastRenderedScrollLeft = scrollLeft;
    _h_render = null;
  }

  void _handleHeaderRowScroll([dom.Event e]) {
    var scrollLeft = _headerRowScroller.scrollLeft;
    if (scrollLeft != _viewport.scrollLeft) {
      _viewport.scrollLeft = scrollLeft;
    }
  }

  void _handleScroll([dom.Event e]) {
    _scrollTop = _viewport.scrollTop;
    scrollLeft = _viewport.scrollLeft;
    int vScrollDist = (_scrollTop - _prevScrollTop).abs();
    int hScrollDist = (scrollLeft - _prevScrollLeft).abs();

    if (hScrollDist != 0) {
      _prevScrollLeft = scrollLeft;
      _headerScroller.scrollLeft = scrollLeft;
      _topPanelScroller.scrollLeft = scrollLeft;
      _headerRowScroller.scrollLeft = scrollLeft;
    }

    if (vScrollDist != 0) {
      vScrollDir = _prevScrollTop < _scrollTop ? 1 : -1;
      _prevScrollTop = _scrollTop;

      // switch virtual pages if needed
      if (vScrollDist < _viewportH) {
        _scrollTo(_scrollTop + pageOffset);
      } else {
        var oldOffset = pageOffset;
        if (h == _viewportH) {
          page = 0;
        } else {
          page = math.min(n - 1, (_scrollTop * ((th - _viewportH) / (h - _viewportH)) * (1 / ph)).floor());
        }
        pageOffset = (page * cj).round();
        if (oldOffset != pageOffset) {
          invalidateAllRows();
        }
      }
    }

    if (hScrollDist != null || vScrollDist != null) {
      if (_h_render != null) {
        _h_render.cancel();
      }

      if ((_lastRenderedScrollTop - _scrollTop).abs() > 20 ||
          (_lastRenderedScrollLeft - _scrollLeft).abs() > 20) {
        if (_gridOptions.forceSyncScrolling || (
            (_lastRenderedScrollTop - _scrollTop).abs() < _viewportH &&
            (_lastRenderedScrollLeft - _scrollLeft).abs() < _viewportW)) {
          render();
        } else {
          _h_render = new async.Timer(new Duration(milliseconds: 50), render);
        }

        _eventBus.fire(core.Events.VIEWPORT_CHANGED, new core.ViewportChanged(this));
      }
    }

    _eventBus.fire(core.Events.SCROLL, new core.Scroll(this, scrollLeft: _scrollLeft, scrollTop: _scrollTop));
  }

  void _asyncPostProcessRows() {
    var dataLength = getDataLength;
    while (_postProcessFromRow <= _postProcessToRow) {
      var row = (vScrollDir >= 0) ? _postProcessFromRow++ : _postProcessToRow--;
      var cacheEntry = _rowsCache[row];
      if (!cacheEntry || row >= dataLength) {
        continue;
      }

      if (_postProcessedRows[row] == null) {
        _postProcessedRows[row] = []; // TODO {}
      }

      _ensureCellNodesInRowsCache(row);
      for (var columnIdx in cacheEntry.cellNodesByColumnIdx) {
        if (!cacheEntry.cellNodesByColumnIdx.containsKey(columnIdx)) {
          continue;
        }

        columnIdx = columnIdx | 0; // TODO

        var m = columns[columnIdx];
        if (m.asyncPostRender && _postProcessedRows[row][columnIdx] == null) {
          var node = cacheEntry.cellNodesByColumnIdx[columnIdx];
          if (node) {
            m.asyncPostRender(node, row, getDataMapItem(row), m);
          }
          _postProcessedRows[row][columnIdx] = true;
        }
      }

      _h_postrender = new async.Timer(_gridOptions.asyncPostRenderDelay, _asyncPostProcessRows);
      return;
    }
  }

  void _updateCellCssStylesOnRenderedRows(String addedHash, List<int> removedHash) {
    dom.HtmlElement node;
    int columnId;
    bool addedRowHash;
    bool removedRowHash;
    for (var row = 0; row < _rowsCache.length; row++) { // TODO check was probably associative array
      removedRowHash = removedHash != null && removedHash[row] != null;
      addedRowHash = addedHash != null && addedHash[row] != null;

      if (removedRowHash) {
        for (columnId in removedRowHash) {
          if (!addedRowHash || removedRowHash[columnId] != addedRowHash[columnId]) {
            node = getCellNode(row, getColumnIndex(columnId));
            if (node != null) {
              node.classes.remove(removedRowHash[columnId]);
            }
          }
        }
      }

      if (addedRowHash) {
        for (columnId in addedRowHash) {
          if (!removedRowHash || removedRowHash[columnId] != addedRowHash[columnId]) {
            node = getCellNode(row, getColumnIndex(columnId));
            if (node != null) {
              node.classes.add(addedRowHash[columnId]);
            }
          }
        }
      }
    }
  }

  void addCellCssStyles(key, hash) {
    if (_cellCssClasses[key] != null) {
      throw "addCellCssStyles: cell CSS hash with key '" + key + "' already exists.";
    }

    _cellCssClasses[key] = hash;
    _updateCellCssStylesOnRenderedRows(hash, null);

    fire('cell-css-style-changed', detail: { "key": key, "hash": hash }); // TODO eventbus.fire
  }

  void removeCellCssStyles(String key) {
    if (_cellCssClasses[key] == null) {
      return;
    }

    _updateCellCssStylesOnRenderedRows(null, _cellCssClasses[key]);
    _cellCssClasses.remove(key);

    _eventBus.fire(core.Events.CELL_CSS_STYLES_CHANGED, new core.CellCssStylesChanged(this, key));
  }

  void setCellCssStyles(String key, List<Map<String,String>> hash) {
    var prevHash = _cellCssClasses[key];

    _cellCssClasses[key] = hash;
    _updateCellCssStylesOnRenderedRows(hash, prevHash);

    _eventBus.fire(core.Events.CELL_CSS_STYLES_CHANGED, new core.CellCssStylesChanged(this, key, hash: hash));
  }

  Map<int,String> getCellCssStyles(int key) {
    return _cellCssClasses[key];
  }

  void flashCell(int row, int cell, int speed) {
    speed = speed != null ? speed : 100;
    if (_rowsCache[row] != null) {
      var $cell = getCellNode(row, cell);

      Function toggleCellClass;
      toggleCellClass = (times) {
        if (!times) {
          return;
        }
        new async.Future.delayed(new Duration(milliseconds: speed),() {
              $cell.queue(() {
                $cell.classes.toggle(_gridOptions.cellFlashingCssClass).dequeue();
                toggleCellClass(times - 1);
              });
            });
      };

      toggleCellClass(4);
    }
  }

  //////////////////////////////////////////////////////////////////////////////////////////////
  // Interactivity

  void _handleMouseWheel(dom.MouseEvent e) {
    var rowNode = tools.closest((e.target as dom.HtmlElement), '.bwu-datagrid-row');
    if (rowNode != _rowNodeFromLastMouseWheelEvent) {
      if (_zombieRowNodeFromLastMouseWheelEvent && _zombieRowNodeFromLastMouseWheelEvent != rowNode) {
        //$canvas.children[0].remove(zombieRowNodeFromLastMouseWheelEvent);
        if(_zombieRowNodeFromLastMouseWheelEvent != null) { // TODO check
          _zombieRowNodeFromLastMouseWheelEvent.remove();
        }
        _zombieRowNodeFromLastMouseWheelEvent = null;
      }
      _rowNodeFromLastMouseWheelEvent = rowNode;
    }
  }

  bool _handleDrag(dom.MouseEvent e, [int dd]) {
    Cell cell = getCellFromEvent(e);
    if (cell == null || !_cellExists(cell.row, cell.cell)) {
      return false;
    }

    var data = _eventBus.fire(core.Events.DRAG_INIT, new core.DragInit(this, dd: dd, causedBy: e));
    if (e.currentTarget == null && e.eventPhase == 0) { // .isImmediatePropagationStopped()) {
      return data.retVal;
    }

    // if nobody claims to be handling drag'n'drop by stopping immediate propagation,
    // cancel out of it
    return false;
  }

  bool _handleDragStart(dom.MouseEvent e, Map dd) {
    var cell = getCellFromEvent(e);
    if (cell != null|| !_cellExists(cell.row, cell.cell)) {
      return false;
    }

    dd['origin-event'] = e;
    var retval = fire('drag-start', detail: dd);  // TODO eventbus.fire
    //var retval = trigger(self.onDragStart, dd, e);
    if(e.defaultPrevented) {
    //if (e.isImmediatePropagationStopped()) {
      //return retval;
      return true;
    }

    return false;
  }

  void _handleDragOver(dom.MouseEvent e, [Map dd]) {
    dd['origin-event'] = e;
     fire('drag', detail: dd) as dom.HtmlElement; // TODO eventbus fire
    //return trigger(self.onDrag, dd, e);
  }

  void _handleDragEnd(dom.MouseEvent e, [Map dd]) {
    dd['origin-event'] = e;
    fire('drag-end', detail: dd);  // TODO eventbus fire
    //trigger(self.onDragEnd, dd, e);
  }

  void _handleKeyDown(dom.KeyboardEvent e) {
    var data = _eventBus.fire(core.Events.KEY_DOWN, new  core.KeyDown(this, new Cell(_activeRow, _activeCell), causedBy: e));
    var handled = data.isImmediatePropagationStopped;

    if (!handled) {
      if (!e.shiftKey && !e.altKey && !e.ctrlKey) {
        if (e.which == 27) {
          if (!getEditorLock.isActive) {
            return; // no editing mode to cancel, allow bubbling and default processing (exit without cancelling the event)
          }
          _cancelEditAndSetFocus();
        } else if (e.which == dom.KeyCode.NUM_SOUTH_EAST) {
          navigatePageDown();
          handled = true;
        } else if (e.which == dom.KeyCode.NUM_NORTH_EAST) {
          navigatePageUp();
          handled = true;
        } else if (e.which == dom.KeyCode.NUM_WEST) {
          handled = navigateLeft();
        } else if (e.which == dom.KeyCode.NUM_EAST) {
          handled = navigateRight();
        } else if (e.which == dom.KeyCode.NUM_NORTH) {
          handled = navigateUp();
        } else if (e.which == dom.KeyCode.NUM_SOUTH) {
          handled = navigateDown();
        } else if (e.which == dom.KeyCode.TAB) {
          handled = navigateNext();
        } else if (e.which == dom.KeyCode.ENTER) {
          if (_gridOptions.editable) {
            if (_currentEditor != null) {
              // adding new row
              if (_activeRow == getDataLength) {
                navigateDown();
              } else {
                _commitEditAndSetFocus();
              }
            } else {
              if (getEditorLock.commitCurrentEdit()) {
                makeActiveCellEditable();
              }
            }
          }
          handled = true;
        }
      } else if (e.which == dom.KeyCode.TAB && e.shiftKey && !e.ctrlKey && !e.altKey) {
        handled = navigatePrev();
      }
    }

    if (handled) {
      // the event has been handled so don't let parent element (bubbling/propagation) or browser (default) handle it
      e.stopPropagation();
      e.preventDefault();
//      try {
//        e.originalEvent.keyCode = 0; // prevent default behaviour for special keys in IE browsers (F3, F5, etc.)
//      }
//      // ignore exceptions - setting the original event's keycode throws access denied exception for "Ctrl"
//      // (hitting control key only, nothing else), "Shift" (maybe others)
//      catch (error) {
//      }
    }
  }

  void _handleClick(dom.MouseEvent e) {
    if (_currentEditor == null) {
      // if this click resulted in some cell child node getting focus,
      // don't steal it back - keyboard events will still bubble up
      // IE9+ seems to default DIVs to tabIndex=0 instead of -1, so check for cell clicks directly.
      if (e.target != dom.document.activeElement || (e.target as dom.HtmlElement).classes.contains("bwu-datagrid-cell")) {
        setFocus();
      }
    }

    var cell = getCellFromEvent(e);
    if (cell == null || (_currentEditor != null && _activeRow == cell.row && _activeCell == cell.cell)) {
      return;
    }

    var data = _eventBus.fire(core.Events.CLICK, new core.Click(this, cell, causedBy: e));
    if (data.isImmediatePropagationStopped) {
      return;
    }

    if ((_activeCell != cell.cell || _activeRow != cell.row) && canCellBeActive(cell.row, cell.cell)) {
      if (!getEditorLock.isActive || getEditorLock.commitCurrentEdit()) {
        scrollRowIntoView(cell.row, false);
        _setActiveCellInternal(getCellNode(cell.row, cell.cell));
      }
    }
  }

  void _handleContextMenu(dom.MouseEvent e) {
    var cell = getCellFromEvent(e);
    //var $cell = tools.closest((e.target as dom.HtmlElement), '.bwu-datagrid-cell', context: $canvas);
    if (cell == null) {
      return;
    }

    // are we editing this cell?
    if (_activeCellNode == cell && _currentEditor != null) {
      return;
    }

    _eventBus.fire(core.Events.CONTEXT_MENU, new core.ContextMenu(this, cell, causedBy: e));
  }

  void _handleDblClick(dom.MouseEvent e) {
    Cell cell = getCellFromEvent(e);
    if (cell == null|| (_currentEditor != null && _activeRow == cell.row && _activeCell == cell.cell)) {
      return;
    }

    var data = _eventBus.fire(core.Events.DOUBLE_CLICK, new core.DoubleClick(this, cell, causedBy: e));
    if (data.isImmediatePropagationStopped) {
      return;
    }

    if (_gridOptions.editable) {
      gotoCell(cell.row, cell.cell, true);
    }
  }

  void _handleHeaderMouseEnter(dom.MouseEvent e) {
    _eventBus.fire(core.Events.HEADER_MOUSE_ENTER, new core.HeaderMouseEnter(this, (e.target as BwuDatagridHeaderColumn).column, causedBy: e));
  }

  void _handleHeaderMouseLeave(dom.MouseEvent e) {
    _eventBus.fire(core.Events.HEADER_MOUSE_LEAVE, new core.HeaderMouseLeave(this, dataset['column'], causedBy: e));
  }

  void _handleHeaderContextMenu(dom.MouseEvent e) {
    var $header = tools.closest((e.target as dom.HtmlElement), ".bwu-datagread-header-column" /*, ".bwu-datagrid-header-columns"*/) as BwuDatagridHeaderColumn;
    var column = $header != null ? $header.column : null;
    _eventBus.fire(core.Events.HEADER_CONTEX_MENU, new core.HeaderContextMenu(this, column, causedBy: e));
  }

  void _handleHeaderClick(dom.MouseEvent e) {
    var $header = tools.closest((e.target as dom.HtmlElement),'.bwu-datagrid-header-column' /*, ".bwu-datagrid-header-columns"*/) as BwuDatagridHeaderColumn;
    var column = $header != null ? $header.column : null;
    if (column != null) {
      _eventBus.fire(core.Events.HEADER_CLICK, new core.HeaderClick(this, column, causedBy: e));
    }
  }

  void _handleMouseEnter(dom.MouseEvent e) {
    _eventBus.fire(core.Events.MOUSE_ENTER, new core.MouseEnter(this, causedBy: e));
  }

  void _handleMouseLeave(dom.MouseEvent e) {
    _eventBus.fire(core.Events.MOUSE_LEAVE, new core.MouseLeave(this, causedBy: e));
  }

  bool _cellExists(int row, int cell) {
    return !(row < 0 || row >= getDataLength || cell < 0 || cell >= columns.length);
  }

  Cell getCellFromPoint(int x, int y) {
    var row = _getRowFromPosition(y);
    var cell = 0;

    var w = 0;
    for (var i = 0; i < columns.length && w < x; i++) {
      w += columns[i].width;
      cell++;
    }

    if (cell < 0) {
      cell = 0;
    }

    return new Cell(row, cell - 1);
  }

  int _getCellFromNode(dom.HtmlElement cellNode) {
    // read column number from .l<columnNumber> CSS class
    var matches = new RegExp(r'(?:\l)(\d+)').firstMatch(cellNode.className);
    //var cls = new RegExp(r'l\d+').allMatches(cellNode.className);
    if (matches == null) {
      throw "getCellFromNode: cannot get cell - ${cellNode.className}";
    }
    return tools.parseInt(matches.group(1));
  }

  int _getRowFromNode(dom.HtmlElement rowNode) {
    for (final row in _rowsCache.keys) { // TODO in rowsCache) {
      if (_rowsCache[row] != null && _rowsCache[row].rowNode == rowNode) {
        return row;
      }
    }

    return null;
  }

  Cell getCellFromEvent(dom.Event e) {
    var $cell = tools.closest((e.target as dom.HtmlElement), '.bwu-datagrid-cell', context: _canvas);
    if ($cell == null) {
      return null;
    }

    var row = _getRowFromNode($cell.parentNode);
    var cell = _getCellFromNode($cell);

    if (row == null || cell == null) {
      return null;
    } else {
      return new Cell(row, cell);
    }
  }

  NodeBox getCellNodeBox(int row, int cell) {
    if (!_cellExists(row, cell)) {
      return null;
    }

    var y1 = _getRowTop(row);
    var y2 = y1 + _gridOptions.rowHeight - 1;
    var x1 = 0;
    for (var i = 0; i < cell; i++) {
      x1 += columns[i].width;
    }
    var x2 = x1 + columns[cell].width;

    // TODO shouldn't this be a rectangle?
    return new NodeBox(top: y1, left: x1, bottom: y2, right: x2);
  }

  //////////////////////////////////////////////////////////////////////////////////////////////
  // Cell switching

  void resetActiveCell() {
    _setActiveCellInternal(null, false);
  }

  void setFocus() {
    if (_tabbingDirection == -1) {
      _focusSink.focus();
    } else {
      _focusSink2.focus();
    }
  }

  void scrollCellIntoView(int row, int cell, bool doPaging) {
    scrollRowIntoView(row, doPaging);

    var colspan = getColspan(row, cell);
    int intColspan = tools.parseInt(colspan);
    var left = _columnPosLeft[cell],
      right = _columnPosRight[cell + (intColspan > 1 ? intColspan - 1 : 0)],
      scrollRight = _scrollLeft + _viewportW;

    if (left < _scrollLeft) {
      _viewport.scrollLeft = left;
      _handleScroll();
      render();
    } else if (right > scrollRight) {
      _viewport.scrollLeft = math.min(left, right - _viewport.clientWidth);
      _handleScroll();
      render();
    }
  }

  void _setActiveCellInternal(dom.HtmlElement newCell, [bool opt_editMode]) {
    if (_activeCellNode != null) {
      _makeActiveCellNormal();
      _activeCellNode.classes.remove("active");
      if (_rowsCache[_activeRow] != null) {
        _rowsCache[_activeRow].rowNode.classes.remove("active");
      }
    }

    var activeCellChanged = (_activeCellNode != newCell);
    _activeCellNode = newCell;

    if (_activeCellNode != null) {
      _activeRow = _getRowFromNode(_activeCellNode.parentNode);
      _activeCell = _activePosX = _getCellFromNode(_activeCellNode);

      if (opt_editMode == null) {
        opt_editMode = (_activeRow == getDataLength) || _gridOptions.autoEdit;
      }

      _activeCellNode.classes.add("active");
      _rowsCache[_activeRow].rowNode.classes.add("active");

      if (_gridOptions.editable && opt_editMode && _isCellPotentiallyEditable(_activeRow, _activeCell)) {
        if(_h_editorLoader != null) {
          _h_editorLoader.cancel();
        }
        if (_gridOptions.asyncEditorLoading) {
          _h_editorLoader = new async.Timer(_gridOptions.asyncEditorLoadDelay, () {
            makeActiveCellEditable();
          });
        } else {
          makeActiveCellEditable();
        }
      }
    } else {
      _activeRow = _activeCell = null;
    }

    if (activeCellChanged) {
      _eventBus.fire(core.Events.ACTIVE_CELL_CHANGED, new core.ActiveCellChanged(this, getActiveCell()));
    }
  }

  void _clearTextSelection() {
//    if (dom.document.selection && dom.document.selection.empty) {
//      try {
//        //IE fails here if selected element is not in dom
//        dom.document.selection.empty();
//      } catch (e) { }
//    } else
//      if (dom.window.getSelection) {
      var sel = dom.window.getSelection();
      if (sel && sel.removeAllRanges) {
        sel.removeAllRanges();
      }
//    }
  }

  bool _isCellPotentiallyEditable(int row, int cell) {
    var dataLength = getDataLength;
    // is the data for this row loaded?
    if (row < dataLength && getDataMapItem(row) == null) {
      return false;
    }

    // are we in the Add New row?  can we create new from this cell?
    if (columns[cell].cannotTriggerInsert && row >= dataLength) {
      return false;
    }

    // does this cell have an editor?
    if (_getEditor(row, cell) == null) {
      return false;
    }

    return true;
  }

  void _makeActiveCellNormal() {
    if (_currentEditor == null) {
      return;
    }
    _eventBus.fire(core.Events.BEFORE_CELL_EDITOR_DESTROY, new core.BeforeCellEditorDestroy(this, _currentEditor));
    _currentEditor.destroy();
    _currentEditor = null;

    if (_activeCellNode != null) {
      var d = getDataMapItem(_activeRow);
      _activeCellNode.classes..remove("editable")..remove("invalid");
      if (d != null) {
        var column = columns[_activeCell];
        Formatter formatter = _getFormatter(_activeRow, column);
        /*activeCellNode.innerHtml =*/ formatter(_activeCellNode, _activeRow, _activeCell, _getDataItemValueForColumn(d, column), column, d);
        _invalidatePostProcessingResults(_activeRow);
      }
    }

    // if there previously was text selected on a page (such as selected text in the edit cell just removed),
    // IE can't set focus to anything else correctly
    if (dom.window.navigator.userAgent.toLowerCase().contains('msie')) {
      _clearTextSelection();
    }

    getEditorLock.deactivate(_editController);
  }

  void makeActiveCellEditable([Editor editor]) {
    if (_activeCellNode == null) {
      return;
    }
    if (!_gridOptions.editable) {
      throw "Grid : makeActiveCellEditable : should never get called when options.editable is false";
    }

    // cancel pending async call if there is one
    if(_h_editorLoader != null) {
      _h_editorLoader.cancel();
    }

    if (!_isCellPotentiallyEditable(_activeRow, _activeCell)) {
      return;
    }

    var columnDef = columns[_activeCell];
    var item = getDataMapItem(_activeRow);

    if(!_eventBus.fire(core.Events.BEFORE_EDIT_CELL, new core.BeforeEditCell(this, cell: new Cell(_activeRow, _activeCell), item: item, column: columnDef)).retVal) {
      setFocus();
      return;
    }

    getEditorLock.activate(_editController);
    _activeCellNode.classes.add("editable");

    // don't clear the cell if a custom editor is passed through
    if (editor == null) {
      _activeCellNode.innerHtml = "";
    }

    if(editor != null) {
      _currentEditor = editor;
    } else {
      _currentEditor = _getEditor(_activeRow, _activeCell);
    }
    _currentEditor = _currentEditor.newInstance(new EditorArgs(
      grid: this,
      gridPosition: _absBox(_container.host),
      position: (_absBox(_activeCellNode)),
      container: _activeCellNode,
      column: columnDef,
      item :  item != null ? item : new Item(),
      commitChanges : _commitEditAndSetFocus,
      cancelChanges : _cancelEditAndSetFocus));

    //currentEditor = new (editor || getEditor(activeRow, activeCell))({
//      'grid': this,
//      'gridPosition': absBox($container.children[0]),
//      'position': absBox(activeCellNode),
//      'container': activeCellNode,
//      'column': columnDef,
//      'item': item || {},
//      'commitChanges': commitEditAndSetFocus,
//      'cancelChanges': cancelEditAndSetFocus
//    });

    if (item != null) {
      _currentEditor.loadValue(item);
    }

    _serializedEditorValue = _currentEditor.serializeValue();

    if (_currentEditor.position != null) {
      _handleActiveCellPositionChange(null);
    }
  }

  void _commitEditAndSetFocus() {
    // if the commit fails, it would do so due to a validation error
    // if so, do not steal the focus from the editor
    if (getEditorLock.commitCurrentEdit()) {
      setFocus();
      if (_gridOptions.autoEdit) {
        navigateDown();
      }
    }
  }

  void _cancelEditAndSetFocus() {
    if (getEditorLock.cancelCurrentEdit()) {
      setFocus();
    }
  }

  NodeBox _absBox(dom.HtmlElement elem) {
    var bcr = elem.getBoundingClientRect();
    var box = new NodeBox(
        top: (bcr.top as double).toInt(),
        left: (bcr.left as double).toInt(),
        bottom: (bcr.bottom as double).toInt(),
        right: (bcr.right as double).toInt(),
        width: (bcr.width as double).toInt(),
        height: (bcr.height as double).toInt(),
        visible: true);
//    var cs = elem.getComputedStyle();
//    var box = new NodeBox(
//      top: elem.offsetTop,
//      left: elem.offsetLeft,
//      bottom: 0,
//      right: 0,
//      width: tools.outerWidth(elem), //tools.parseInt(cs.width) + tools.parseInt(cs.paddingLeft) + tools.parseInt(cs.paddingRight) + tools.parseInt(cs.borderLeft) + tools.parseInt(cs.borderRight), //elem.outerWidth(),
//      height: tools.outerHeight(elem), //parseInt(cs.height) + tools.parseInt(cs.paddingTop) + tools.parseInt(cs.paddingBottom) + tools.parseInt(cs.borderTop) + tools.parseInt(cs.borderBottom), //elem.outerHeight(), // TODO check all other outerWidth/outherHeight if they include border
//      visible: true);
//    box.bottom = box.top + box.height;
//    box.right = box.left + box.width;

    // walk up the tree
//    var offsetParent = elem.offsetParent;
//    while ((elem = tools.getParentElement(elem.parentNode)) != this) {
//      if (box.visible && elem.scrollHeight != elem.offsetHeight && elem.style.overflowY != "visible") {
//        box.visible = box.bottom > elem.scrollTop && box.top < elem.scrollTop + elem.clientHeight;
//      }
//
//      if (box.visible && elem.scrollWidth != elem.offsetWidth && elem.style.overflowX != "visible") {
//        box.visible = box.right > elem.scrollLeft && box.left < elem.scrollLeft + elem.clientWidth;
//      }
//
//      box.left -= elem.scrollLeft;
//      box.top -= elem.scrollTop;
//
//      if (elem == offsetParent) {
//        box.left += elem.offsetLeft;
//        box.top += elem.offsetTop;
//        offsetParent = elem.offsetParent;
//      }
//
//      box.bottom = box.top + box.height;
//      box.right = box.left + box.width;
//    }

    return box;
  }

  NodeBox getActiveCellPosition() {
    return _absBox(_activeCellNode);
  }

  NodeBox getGridPosition() {
    return _absBox(_container.host);
  }

  void _handleActiveCellPositionChange(dom.Event e) {
    if (_activeCellNode == null) {
      return;
    }

    _eventBus.fire(core.Events.ACTIVE_CELL_POSITION_CHANGED, new core.ActiveCellPositionChanged(this));

    if (_currentEditor != null) {
      var cellBox = getActiveCellPosition();
      //if (currentEditor.show && currentEditor.hide) {
        if (!cellBox.visible) {
          _currentEditor.hide(); // TODO show/hide
        } else {
          _currentEditor.show();
        }
      //}

      _currentEditor.position(cellBox);
    }
  }

  Editor getCellEditor() {
    return _currentEditor;
  }

  Cell getActiveCell() {
    if (_activeCellNode == null) {
      return null;
    } else {
      return new Cell(_activeRow, _activeCell);
    }
  }

  dom.HtmlElement getActiveCellNode() {
    return _activeCellNode;
  }

  void scrollRowIntoView(int row, bool doPaging) {
    var rowAtTop = row * _gridOptions.rowHeight;
    var rowAtBottom = (row + 1) * _gridOptions.rowHeight - _viewportH + (_viewportHasHScroll ? scrollbarDimensions.y : 0);

    // need to page down?
    if ((row + 1) * _gridOptions.rowHeight > _scrollTop + _viewportH + pageOffset) {
      _scrollTo(doPaging ? rowAtTop : rowAtBottom);
      render();
    }
    // or page up?
    else if (row * _gridOptions.rowHeight < _scrollTop + pageOffset) {
      _scrollTo(doPaging ? rowAtBottom : rowAtTop);
      render();
    }
  }

  void scrollRowToTop(int row) {
    _scrollTo(row * _gridOptions.rowHeight);
    render();
  }

  void _scrollPage(int dir) {
    var deltaRows = dir * _numVisibleRows;
    _scrollTo((_getRowFromPosition(_scrollTop) + deltaRows) * _gridOptions.rowHeight);
    render();

    if (_gridOptions.enableCellNavigation && _activeRow != null) {
      var row = _activeRow + deltaRows;
      var dataLengthIncludingAddNew = _getDataLengthIncludingAddNew();
      if (row >= dataLengthIncludingAddNew) {
        row = dataLengthIncludingAddNew - 1;
      }
      if (row < 0) {
        row = 0;
      }

      var cell = 0, prevCell = null;
      var prevActivePosX = _activePosX;
      while (cell <= _activePosX) {
        if (canCellBeActive(row, cell)) {
          prevCell = cell;
        }
        cell += getColspan(row, cell);
      }

      if (prevCell != null) {
        _setActiveCellInternal(getCellNode(row, prevCell));
        _activePosX = prevActivePosX;
      } else {
        resetActiveCell();
      }
    }
  }

  void navigatePageDown() => _scrollPage(1);

  void navigatePageUp() =>  _scrollPage(-1);

  String getColspan(int row, int cell) {
    ItemMetadata metadata = dataView != null && dataView.getItemMetadata != null ? dataView.getItemMetadata(row) : null;
    if (metadata == null || metadata.columns == null) {
      return '1';
    }

    ColumnMetadata columnData = metadata.columns[columns[cell].id] != null ? metadata.columns[columns[cell].id] : metadata.columns[cell];
    String colspan = columnData != null ? columnData.colspan : null;
    if (colspan == "*") {
      colspan = '${columns.length - cell}';
    } else {
      colspan = colspan != null ? colspan : '1';
    }

    return colspan;
  }

  int _findFirstFocusableCell(int row) {
    var cell = 0;
    while (cell < columns.length) {
      if (canCellBeActive(row, cell)) {
        return cell;
      }
      cell += getColspan(row, cell);
    }
    return null;
  }

  int _findLastFocusableCell(int row) {
    var cell = 0;
    var lastFocusableCell = null;
    while (cell < columns.length) {
      if (canCellBeActive(row, cell)) {
        lastFocusableCell = cell;
      }
      cell += getColspan(row, cell);
    }
    return lastFocusableCell;
  }

  CellPos _gotoRight(int row, int cell, int posX) {
    if (cell >= columns.length) {
      return null;
    }

    do {
      cell += tools.parseInt(getColspan(row, cell));
    }
    while (cell < columns.length && !canCellBeActive(row, cell));

    if (cell < columns.length) {
      return new CellPos(row: row, cell: cell, posX: cell);
    }
    return null;
  }

  CellPos _gotoLeft(int row, int cell, int posX) {
    if (cell <= 0) {
      return null;
    }

    var firstFocusableCell = _findFirstFocusableCell(row);
    if (firstFocusableCell == null || firstFocusableCell >= cell) {
      return null;
    }

    var prev = new CellPos(row: row, cell: firstFocusableCell, posX: firstFocusableCell);
    var pos;
    while (true) {
      pos = _gotoRight(prev.row, prev.cell, prev.cell); //prev.posX']);
      if (pos == null) {
        return null;
      }
      if (pos.cell >= cell) {
        return prev;
      }
      prev = pos;
    }
  }

  CellPos _gotoDown(int row, int cell, int posX) {
    var prevCell;
    var dataLengthIncludingAddNew = _getDataLengthIncludingAddNew();
    while (true) {
      if (++row >= dataLengthIncludingAddNew) {
        return null;
      }

      prevCell = cell = 0;
      while (cell <= posX) {
        prevCell = cell;
        cell += tools.parseInt(getColspan(row, cell));
      }

      if (canCellBeActive(row, prevCell)) {
        return new CellPos(row: row,cell: prevCell, posX: posX);
      }
    }
  }

  CellPos _gotoUp(int row, int cell, int posX) {
    var prevCell;
    while (true) {
      if (--row < 0) {
        return null;
      }

      prevCell = cell = 0;
      while (cell <= posX) {
        prevCell = cell;
        cell += tools.parseInt(getColspan(row, cell));
      }

      if (canCellBeActive(row, prevCell)) {
        return new CellPos(
          row: row,
          cell: prevCell,
          posX: posX
        );
      }
    }
  }

  CellPos _gotoNext(int row, int cell, int posX) {
    if (row == null && cell == null) {
      row = cell = posX = 0;
      if (canCellBeActive(row, cell)) {
        return new CellPos(
          row: row,
          cell: cell,
          posX: cell
        );
      }
    }

    var pos = _gotoRight(row, cell, posX);
    if (pos != null) {
      return pos;
    }

    var firstFocusableCell = null;
    var dataLengthIncludingAddNew = _getDataLengthIncludingAddNew();
    while (++row < dataLengthIncludingAddNew) {
      firstFocusableCell = _findFirstFocusableCell(row);
      if (firstFocusableCell != null) {
        return new CellPos(
          row: row,
          cell: firstFocusableCell,
          posX: firstFocusableCell
        );
      }
    }
    return null;
  }

  CellPos _gotoPrev(int row, int cell, int posX) {
    if (row == null && cell == null) {
      row = _getDataLengthIncludingAddNew() - 1;
      cell = posX = columns.length - 1;
      if (canCellBeActive(row, cell)) {
        return new CellPos(
          row: row,
          cell: cell,
          posX: cell
        );
      }
    }

    CellPos pos;
    var lastSelectableCell;
    while (pos == null) {
      pos = _gotoLeft(row, cell, posX);
      if (pos != null) {
        break;
      }
      if (--row < 0) {
        return null;
      }

      cell = 0;
      lastSelectableCell = _findLastFocusableCell(row);
      if (lastSelectableCell != null) {
        pos = new CellPos(
          row: row,
          cell: lastSelectableCell,
          posX: lastSelectableCell
        );
      }
    }
    return pos;
  }

  bool navigateRight() {
    return _navigate("right");
  }

  bool navigateLeft() {
    return _navigate("left");
  }

  bool navigateDown() {
    return _navigate("down");
  }

  bool navigateUp() {
    return _navigate("up");
  }

  bool navigateNext() {
    return _navigate("next");
  }

  bool navigatePrev() {
    return _navigate("prev");
  }

  /**
   * @param {string} dir Navigation direction.
   * @return {boolean} Whether navigation resulted in a change of active cell.
   */
  bool _navigate(String dir) {
    if (!_gridOptions.enableCellNavigation) {
      return false;
    }

    if (_activeCellNode == null&& dir != "prev" && dir != "next") {
      return false;
    }

    if (!getEditorLock.commitCurrentEdit()) {
      return true;
    }
    setFocus();

    var tabbingDirections = {
      "up": -1,
      "down": 1,
      "left": -1,
      "right": 1,
      "prev": -1,
      "next": 1
    };
    _tabbingDirection = tabbingDirections[dir];

    var stepFunctions = {
      "up": _gotoUp,
      "down": _gotoDown,
      "left": _gotoLeft,
      "right": _gotoRight,
      "prev": _gotoPrev,
      "next": _gotoNext
    };
    var stepFn = stepFunctions[dir];
    var pos = stepFn(_activeRow, _activeCell, _activePosX);
    if (pos != null) {
      var isAddNewRow = (pos.row == getDataLength);
      scrollCellIntoView(pos.row, pos.cell, !isAddNewRow);
      _setActiveCellInternal(getCellNode(pos.row, pos.cell));
      _activePosX = pos.posX;
      return true;
    } else {
      _setActiveCellInternal(getCellNode(_activeRow, _activeCell));
      return false;
    }
  }

  dom.HtmlElement getCellNode(int row, int cell) {
    if (_rowsCache[row] != null) {
      _ensureCellNodesInRowsCache(row);
      var c = _rowsCache[row].cellNodesByColumnIdx[cell];
      return c;
    }
    return null;
  }

  void setActiveCell(int row, int cell) {
    if (!_initialized) { return; }
    if (row > getDataLength || row < 0 || cell >= columns.length || cell < 0) {
      return;
    }

    if (!_gridOptions.enableCellNavigation) {
      return;
    }

    scrollCellIntoView(row, cell, false);
    _setActiveCellInternal(getCellNode(row, cell), false);
  }

  bool canCellBeActive(int row, int cell) {
    if (!_gridOptions.enableCellNavigation || row >= _getDataLengthIncludingAddNew() ||
        row < 0 || cell >= columns.length || cell < 0) {
      return false;
    }

    ItemMetadata rowMetadata = dataView != null && dataView.getItemMetadata != null ? dataView.getItemMetadata(row) : null;
    if (rowMetadata != null && rowMetadata.focusable == true) {
      return rowMetadata.focusable;
    }

    ColumnMetadata columnMetadata = rowMetadata != null ? rowMetadata.columns : null;
    if (columnMetadata != null && columnMetadata[columns[cell].id] != null && columnMetadata[columns[cell].id].focusable is bool) {
      return columnMetadata[columns[cell].id].focusable;
    }
    if (columnMetadata != null && columnMetadata[cell] != null && columnMetadata[cell].focusable is bool) {
      return columnMetadata[cell].focusable;
    }

    return columns[cell].focusable;
  }

  bool canCellBeSelected(row, cell) {
    if (row >= getDataLength || row < 0 || cell >= columns.length || cell < 0) {
      return false;
    }

    ItemMetadata rowMetadata = dataView!= null && dataView.getItemMetadata != null ? dataView.getItemMetadata(row) : null;
    if (rowMetadata && rowMetadata.selectable is bool) {
      return rowMetadata.selectable;
    }

    ColumnMetadata columnMetadata;
    if(rowMetadata != null && rowMetadata.columns != null) {
      columnMetadata =rowMetadata.columns[columns[cell].id];
    } else {
      columnMetadata = rowMetadata.columns[cell];
    }
    if (columnMetadata != null && columnMetadata.selectable is bool) {
      return columnMetadata.selectable;
    }

    return columns[cell].selectable;
  }

  void gotoCell(int row, int cell, bool forceEdit) {
    if (!_initialized) { return; }
    if (!canCellBeActive(row, cell)) {
      return;
    }

    if (!getEditorLock.commitCurrentEdit()) {
      return;
    }

    scrollCellIntoView(row, cell, false);

    var newCell = getCellNode(row, cell);

    // if selecting the 'add new' row, start editing right away
    _setActiveCellInternal(newCell, forceEdit || (row == getDataLength) || _gridOptions.autoEdit);

    // if no editor was created, set the focus back on the grid
    if (_currentEditor == null) {
      setFocus();
    }
  }


  //////////////////////////////////////////////////////////////////////////////////////////////
  // IEditor implementation for the editor lock
  bool _commitCurrentEdit() {
    var item = getDataMapItem(_activeRow);
    var column = columns[_activeCell];

    if (_currentEditor != null) {
      if (_currentEditor.isValueChanged) {
        var validationResults = _currentEditor.validate();

        if (validationResults.isValid) {
          if (_activeRow < getDataLength) {
            EditCommand editCommand;
            editCommand = new EditCommand(
              row: _activeRow,
              cell: _activeCell,
              editor: _currentEditor,
              serializedValue: _currentEditor.serializeValue(),
              prevSerializedValue: _serializedEditorValue,
              execute: () {
                EditCommand cmd = editCommand;
                cmd.editor.applyValue(item, cmd.serializedValue);
                updateRow(cmd.row);
                _eventBus.fire(core.Events.CELL_CHANGED, new core.CellChanged(this, new Cell(_activeRow, _activeCell), item));
              },
              undo: () {
                EditCommand cmd = editCommand;
                cmd.editor.applyValue(item, cmd.prevSerializedValue);
                updateRow(cmd.row);
                _eventBus.fire(core.Events.CELL_CHANGED, new core.CellChanged(this, new Cell(_activeRow, _activeCell), item));
              });

            if (_gridOptions.editCommandHandler != null) {
              _makeActiveCellNormal();
              _gridOptions.editCommandHandler(item, column, editCommand);
            } else {
              editCommand.execute();
              _makeActiveCellNormal();
            }

          } else {
            var newItem = new Item();
            _currentEditor.applyValue(newItem, _currentEditor.serializeValue());
            _makeActiveCellNormal();
            _eventBus.fire(core.Events.ADD_NEW_ROW, new core.AddNewRow(this, item, column));
          }

          // check whether the lock has been re-acquired by event handlers
          return !getEditorLock.isActive;
        } else {
          // Re-add the CSS class to trigger transitions, if any.
          _activeCellNode.classes.remove("invalid");
          _activeCellNode.style.width;  // force layout // TODO ob das in Dart so funktioniert
          _activeCellNode.classes.add("invalid");

          _eventBus.fire(core.Events.VALIDATION_ERROR, new core.ValidationError(this,
              editor: _currentEditor,
              cellNode: _activeCellNode,
              validationResults: validationResults,
              cell: new Cell(_activeRow, _activeCell),
              column: column));

          _currentEditor.focus();
          return false;
        }
      }

      _makeActiveCellNormal();
    }
    return true;
  }

  bool _cancelCurrentEdit() {
    _makeActiveCellNormal();
    return true;
  }

  List<int> _rowsToRanges(List<int> rows) {
    var ranges = [];
    var lastCell = columns.length - 1;
    for (var i = 0; i < rows.length; i++) {
      ranges.add(new Range(fromRow: rows[i], fromCell: 0, toRow: rows[i], toCell: lastCell));
    }
    return ranges;
  }

  List<int> getSelectedRows() {
    if (_selectionModel == null) {
      throw "Selection model is not set";
    }
    return _selectedRows;
  }

  void setSelectedRows(List<int> rows) {
    if (_selectionModel == null) {
      throw "Selection model is not set";
    }
    _selectionModel.setSelectedRanges(_rowsToRanges(rows));
  }


  //////////////////////////////////////////////////////////////////////////////////////////////
  // Debug
  void debug () {
    var s =
    "counter_rows_rendered:  ${_counter_rows_rendered}"
    "counter_rows_removed:  ${_counter_rows_removed}"
    "renderedRows:  ${_renderedRows}"
    "numVisibleRows:  ${_numVisibleRows}"
    "maxSupportedCssHeight:  ${maxSupportedCssHeight}"
    "n(umber of pages):  ${n}"
    "(current) page:  ${page}"
    "page height (ph):  ${ph}";
    "vScrollDir:  ${vScrollDir}";

    dom.window.alert(s);
  }

  // a debug helper to be able to access private members
//    this.eval = function (expr) {
//      return eval(expr);
//    };

  //////////////////////////////////////////////////////////////////////////////////////////////
  // Public API

//    $.extend(this, {
//      "slickGridVersion": "2.1",

    // Events
//      "onScroll": new Slick.Event(),
//      "onSort": new Slick.Event(),
//      "onHeaderMouseEnter": new Slick.Event(),
//      "onHeaderMouseLeave": new Slick.Event(),
//      "onHeaderContextMenu": new Slick.Event(),
//      "onHeaderClick": new Slick.Event(),
//      "onHeaderCellRendered": new Slick.Event(),
//      "onBeforeHeaderCellDestroy": new Slick.Event(),
//      "onHeaderRowCellRendered": new Slick.Event(),
//      "onBeforeHeaderRowCellDestroy": new Slick.Event(),
//      "onMouseEnter": new Slick.Event(),
//      "onMouseLeave": new Slick.Event(),
//      "onClick": new Slick.Event(),
//      "onDblClick": new Slick.Event(),
//      "onContextMenu": new Slick.Event(),
//      "onKeyDown": new Slick.Event(),
//      "onAddNewRow": new Slick.Event(),
//      "onValidationError": new Slick.Event(),
//      "onViewportChanged": new Slick.Event(),
//      "onColumnsReordered": new Slick.Event(),
//      "onColumnsResized": new Slick.Event(),
//      "onCellChange": new Slick.Event(),
//      "onBeforeEditCell": new Slick.Event(),
//      "onBeforeCellEditorDestroy": new Slick.Event(),
//      "onBeforeDestroy": new Slick.Event(),
//      "onActiveCellChanged": new Slick.Event(),
//      "onActiveCellPositionChanged": new Slick.Event(),
//      "onDragInit": new Slick.Event(),
//      "onDragStart": new Slick.Event(),
//      "onDrag": new Slick.Event(),
//      "onDragEnd": new Slick.Event(),
//      "onSelectedRowsChanged": new Slick.Event(),
//      "onCellCssStylesChanged": new Slick.Event(),




      async.Stream<core.Click> get onBwuClick =>
          _eventBus.onEvent(core.Events.CLICK);

      async.Stream<core.Click> get onBwuContextMenu =>
          _eventBus.onEvent(core.Events.CONTEXT_MENU);

      async.Stream<core.HeaderMouseEnter> get onBwuHeaderMouseEnter =>
          _eventBus.onEvent(core.Events.HEADER_MOUSE_ENTER);

      async.Stream<core.HeaderMouseLeave> get onBwuHeaderMouseLeave =>
      _eventBus.onEvent(core.Events.HEADER_MOUSE_LEAVE);

      async.Stream<core.MouseEnter> get onBwuMouseEnter =>
          _eventBus.onEvent(core.Events.MOUSE_ENTER);


      async.Stream<core.MouseLeave> get onBwuMouseLeave =>
          _eventBus.onEvent(core.Events.MOUSE_LEAVE);

}
//  /**
//   * on before--destory
//   */
//  static const ON_BEFORE_DESTROY = 'before-destory';
//  async.Stream<dom.CustomEvent> get onBeforeDestory =>
//      BwuDatagrid._onBeforeDestory.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onBeforeDestory =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_BEFORE_DESTROY);

//  /**
//   * on before-header-cell-destory
//   */
//  static const ON_BEFORE_HEADER_CELL_DESTROY = 'before-header-cell-destory';
//  async.Stream<dom.CustomEvent> get onBeforeHeaderCellDestory =>
//      BwuDatagrid._onBeforeHeaderCellDestory.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onBeforeHeaderCellDestory =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_BEFORE_HEADER_CELL_DESTROY);

//  /**
//   * on header-cell-rendered
//   */
//  static const ON_HEADER_CELL_RENDERED = 'header-cell-rendered';
//  async.Stream<dom.CustomEvent> get onHeaderCellRendered =>
//      BwuDatagrid._onHeaderCellRendered.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onHeaderCellRendered =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_HEADER_CELL_RENDERED);

//  /**
//   * on header-row-cell-rendered
//   */
//  static const ON_HEADER_ROW_CELL_RENDERED = 'header-row-cell-rendered';
//  async.Stream<dom.CustomEvent> get onHeaderRowCellRendered =>
//      BwuDatagrid._onHeaderRowCellRendered.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onHeaderRowCellRendered =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_HEADER_ROW_CELL_RENDERED);

//  /**
//   * on sort
//   */
//  static const ON_SORT = 'sort';
//  async.Stream<dom.CustomEvent> get onSort =>
//      BwuDatagrid._onSort.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onSort =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_SORT);
//
//  /**
//   * on columns-resized
//   */
//  static const ON_COLUMNS_RESIZED = 'columns-resized';
//  async.Stream<dom.CustomEvent> get onColumnsResized =>
//      BwuDatagrid._onColumnsResized.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onColumnsResized =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_COLUMNS_RESIZED);

//  /**
//   * on columns-reordered
//   */
//  static const ON_COLUMNS_REORDERED = 'columns-reordered';
//  async.Stream<dom.CustomEvent> get onColumnsReordered =>
//      BwuDatagrid._onColumnsReordered.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onColumnsReordered =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_COLUMNS_REORDERED);

//  /**
//   * on selected-rows-changed
//   */
//  static const ON_SELECTED_ROWS_CHANGED = 'selected-rows-changed';
//  async.Stream<dom.CustomEvent> get onSelectedRowsChanged =>
//      BwuDatagrid._onSelectedRowsChanged.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onSelectedRowsChanged =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_SELECTED_ROWS_CHANGED);

//  /**
//   * on viewport-changed
//   */
//  static const ON_VIEWPORT_CHANGED = 'viewport-changed';
//  async.Stream<dom.CustomEvent> get onViewportChanged =>
//      BwuDatagrid._onViewportChanged.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onViewportChanged =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_VIEWPORT_CHANGED);

//  /**
//   * on cell-css-styles-changed
//   */
//  static const ON_CELL_CSS_STYLES_CHANGED = 'cell-css-styles-changed';
//  async.Stream<dom.CustomEvent> get onCellCssStylesChanged =>
//      BwuDatagrid._onCellCssStylesChanged.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onCellCssStylesChanged =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_CELL_CSS_STYLES_CHANGED);


//  /**
//   * on header-mouse-leave
//   */
//  static const ON_HEADER_CONTEXT_MENU = 'header-context-menu';
//  async.Stream<dom.CustomEvent> get onHeaderContextMenu =>
//      BwuDatagrid._onHeaderContextMenu.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onHeaderContextMenu =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_HEADER_CONTEXT_MENU);

//  /**
//   * on header-click
//   */
//  static const ON_HEADER_CLICK = 'header-click';
//  async.Stream<dom.CustomEvent> get onHeaderClick =>
//      BwuDatagrid._onHeaderClick.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onHeaderClick =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_HEADER_CLICK);

//  /**
//   * on active-cell-changed
//   */
//  static const ON_ACTIVE_CELL_CHANGED = 'active-cell-changed';
//  async.Stream<dom.CustomEvent> get onActiveCellChanged =>
//      BwuDatagrid._onActiveCellChanged.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onActiveCellChanged =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_ACTIVE_CELL_CHANGED);

//  /**
//   * on before-cell-editor-destroy
//   */
//  static const ON_BEFORE_CELL_EDITOR_DESTROY = 'before-cell-editor-destroy';
//  async.Stream<dom.CustomEvent> get onBeforeCellEditorDestroy =>
//      BwuDatagrid._onBeforeCellEditorDestroy.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onBeforeCellEditorDestroy =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_BEFORE_CELL_EDITOR_DESTROY);

//  /**
//   * on before-edit-cell
//   */
//  static const ON_BEFORE_EDIT_CELL = 'before-edit-cell';
//  async.Stream<dom.CustomEvent> get onBeforeEditCell =>
//      BwuDatagrid._onBeforeEditCell.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvenHeaderMouseentert> _onBeforeEditCell =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_BEFORE_EDIT_CELL);

//  /**
//   * on active-cell-position-changed
//   */
//  static const ON_ACTIVE_CELL_POSITION_CHANGED = 'active-cell-position-changed';
//  async.Stream<dom.CustomEvent> get onActiveCellPositionChanged =>
//      BwuDatagrid._onActiveCellPositionChanged.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onActiveCellPositionChanged =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_ACTIVE_CELL_POSITION_CHANGED);

//  /**
//   * on cell-changed
//   */
//  static const ON_CELL_CHANGED = 'cell-changed';
//  async.Stream<dom.CustomEvent> get onCellChanged =>
//      BwuDatagrid._onCellChanged.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onCellChanged =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_CELL_CHANGED);

//  /**
//   * on add-new-row
//   */
//  static const ON_ADD_NEW_ROW = 'add-new-row';
//  async.Stream<dom.CustomEvent> get onAddNewRow =>
//      BwuDatagrid._onAddNewRow.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onAddNewRow =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_ADD_NEW_ROW);

//  /**
//   * on validation-error
//   */
//  static const ON_VALIDATION_ERROR = 'validation-error';
//  async.Stream<dom.CustomEvent> get onValidationError =>
//      BwuDatagrid._onValidationError.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onValidationError =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_VALIDATION_ERROR);

//  /**
//   * on drag-init
//   */
//  static const ON_DRAG_INIT = 'drag-init';
//  async.Stream<dom.CustomEvent> get onDragInit =>
//      BwuDatagrid._onDragInit.forTarget(this);
//
//  static const dom.EventStreamProvider<dom.CustomEvent> _onDragInit =
//      const dom.EventStreamProvider<dom.CustomEvent>(ON_DRAG_INIT);