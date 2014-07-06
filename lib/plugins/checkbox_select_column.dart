library bwu_dart.bwu_datagrid.checkbox_select_column;

import 'dart:html' as dom;
import 'dart:async' as async;

import 'package:bwu_datagrid/datagrid/helpers.dart';
import 'package:bwu_datagrid/bwu_datagrid.dart';
import 'package:bwu_datagrid/core/core.dart' as core;
import 'package:bwu_datagrid/formatters/formatters.dart';
import 'package:bwu_datagrid/plugins/plugin.dart';


class CheckboxSelectionFormatter extends Formatter {
  Map<int, bool> selectedRowsLookup;
  CheckboxSelectionFormatter(this.selectedRowsLookup);
  @override
  void call(dom.HtmlElement target, int row, int cell, dynamic value, Column columnDef, DataItem dataContext) {
    target.children.clear();

    if (dataContext != null) {
      target.append(new dom.CheckboxInputElement()..checked = selectedRowsLookup.containsKey(row));
    }
  }
}


class CheckboxSelectColumn extends Column implements Plugin {

  BwuDatagrid _grid;
  BwuDatagrid get grid => _grid;

  //var _handler = new Slick.EventHandler();
  List<async.StreamSubscription> _subscriptions = [];
  Map<int,bool>_selectedRowsLookup = {};
  CheckboxSelectColumn({String id: '_checkbox_selector', String cssClass, toolTip: 'Select/Deselect All', int width: 30})
  : super(id: id, cssClass: cssClass, toolTip: toolTip, width: width,
      name: 'Column selector', nameElement: new dom.CheckboxInputElement() , field: 'sel', resizable: false,
      sortable: false) {
    formatter = new CheckboxSelectionFormatter(_selectedRowsLookup);
  }

  void init(BwuDatagrid grid) {
    _grid = grid;

    _subscriptions
      ..add(_grid.onBwuSelectedRowsChanged.listen(handleSelectedRowsChanged))
      ..add(_grid.onBwuClick.listen(handleClick))
      ..add(_grid.onBwuHeaderClick.listen(handleHeaderClick))
      ..add(_grid.onBwuKeyDown.listen(handleKeyDown));
  }

  void destroy() {
    //_handler.unsubscribeAll();
    _subscriptions.forEach((e) => e.cancel());
  }

  void handleSelectedRowsChanged(core.SelectedRowsChanged e) {
    List<int> selectedRows = _grid.getSelectedRows();
    Map lookup = {};
    int row;
    for (int i = 0; i < selectedRows.length; i++) {
      row = selectedRows[i];
      lookup[row] = true;
      if (lookup[row] != _selectedRowsLookup[row]) {
        _grid.invalidateRow(row);
        _selectedRowsLookup.remove(row);
      }
    }
    for (final i in _selectedRowsLookup.keys) {
      _grid.invalidateRow(i);
    }
    _selectedRowsLookup = lookup;
    (formatter as CheckboxSelectionFormatter).selectedRowsLookup = _selectedRowsLookup;
    _grid.render();

    if (selectedRows.length > 0 && selectedRows.length == _grid.getDataLength) {
      _grid.updateColumnHeader(id, null, toolTip, nameElement: new dom.CheckboxInputElement()..checked = true);
    } else {
      _grid.updateColumnHeader(id, null, toolTip, nameElement: new dom.CheckboxInputElement());
    }
  }

  void handleKeyDown(core.KeyDown e) {
    if (e.causedBy.which == 32) {
      if (_grid.getColumns[e.cell.cell].id == id) {
        // if editing, try to commit
        if (!_grid.getEditorLock.isActive || _grid.getEditorLock.commitCurrentEdit()) {
          toggleRowSelection(e.cell.row);
        }
        e.preventDefault();
        e.stopImmediatePropagation();
      }
    }
  }

  void handleClick(core.Click e) {
    // clicking on a row select checkbox
    if (_grid.getColumns[e.cell.cell].id == id && e.causedBy.target is dom.CheckboxInputElement) {
      // if editing, try to commit
      if (_grid.getEditorLock.isActive && !_grid.getEditorLock.commitCurrentEdit()) {
        e.preventDefault();
        e.stopImmediatePropagation();
        return;
      }

      toggleRowSelection(e.cell.row);
      e.stopPropagation();
      e.stopImmediatePropagation();
    }
  }

  void toggleRowSelection(int row) {
    if (_selectedRowsLookup.containsKey(row)) {
      _grid.setSelectedRows(_grid.getSelectedRows()..remove(row));
    } else {
      _grid.setSelectedRows(_grid.getSelectedRows()..add(row));
    }
  }

  void handleHeaderClick(core.HeaderClick e) {
    if (e.column.id == id && e.causedBy.target is dom.CheckboxInputElement) {
      // if editing, try to commit
      if (_grid.getEditorLock.isActive && !_grid.getEditorLock.commitCurrentEdit()) {
        e.preventDefault();
        e.stopImmediatePropagation();
        return;
      }

      if ((e.causedBy.target as dom.CheckboxInputElement).checked) {
        var rows = [];
        for (var i = 0; i < _grid.getDataLength; i++) {
          rows.add(i);
        }
        _grid.setSelectedRows(rows);
      } else {
        _grid.setSelectedRows([]);
      }
      e.stopPropagation();
      e.stopImmediatePropagation();
    }
  }
}