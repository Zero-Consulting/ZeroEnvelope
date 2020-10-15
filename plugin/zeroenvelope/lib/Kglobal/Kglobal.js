
var groups_id = [];
var thermal_bridges_id = [];

function hide_main_divs() {
  var main_divs = document.querySelectorAll("#main > div");
  for (var i = 0; i < main_divs.length; i++) {
    main_divs[i].classList.add("hide");
  }
}

function unselect_left() {
  var lis = document.querySelectorAll("#left > ul > li:not(.edit) > ul > li.selected");
  if (lis.length > 0) {
    lis[0].classList.remove("selected");
  }

  var uls = document.querySelectorAll("#left > ul:not(.hide):not(.cte)");
  for (var i = 0; i < uls.length; i++) {
    var spans = uls[i].getElementsByTagName("SPAN")
    for (var j = 1; j < spans.length; j++) {
      spans[j].classList.add("hide");
    }
  }

  var tabs = document.getElementById("output").getElementsByClassName("btn btn-success");
  if (tabs.length === 0) { hide_main_divs(); }
}

function select_tab(tab) {
  var tabs = document.getElementById("output").getElementsByTagName("button");
  for (var i = 0; i < tabs.length; i++) {
    tabs[i].className = tabs[i].className.replace("btn btn-success", "btn btn-secondary");
  }

  unselect_left();

  tabs = document.getElementById("input").getElementsByTagName("button");
  for (var i = 0; i < tabs.length; i++) {
    tabs[i].className = tabs[i].className.replace("btn btn-success", "btn btn-secondary");
  }
  tab.className = tab.className.replace("btn btn-secondary", "btn btn-success");

  var construction_sets = document.getElementById("construction_sets").parentElement;
  var constructions = document.getElementById("constructions").parentElement;
  var materials = document.getElementById("materials").parentElement;
  var glazings = document.getElementById("glazings").parentElement;
  var air_gaps = document.getElementById("air_gaps").parentElement;
  var frame_and_dividers = document.getElementById("frames").parentElement;
  var thermal_bridges = document.getElementById("thermal_bridges").parentElement;

  var left = document.getElementById("left");
  var right = document.getElementById("right");
  right.classList.remove("hide");

  var lis = document.querySelectorAll("#left > ul > li:not(.edit), #right > ul > li:not(.edit)");
  for (var i = 0; i < lis.length; i++) {
    var li = lis[i];
    if (!li.classList.contains("open")) { continue; }
    li.classList.toggle("open");
  }

  switch (tab.value) {
    case "construction_sets":
      construction_sets.classList.remove("hide");
      construction_sets.getElementsByClassName("edit")[0].classList.remove("hide");
      left.appendChild(construction_sets);

      constructions.classList.remove("hide");
      constructions.getElementsByClassName("edit")[0].classList.add("hide");
      right.appendChild(constructions);

      glazings.classList.remove("hide");
      glazings.getElementsByClassName("edit")[0].classList.add("hide");
      right.appendChild(glazings);

      for (var i = 0; i < groups_id.length; i++) {
        group = document.getElementById(groups_id[i]).parentElement
        group.classList.add("hide");
      }
      air_gaps.classList.add("hide");
      materials.classList.add("hide");
      frame_and_dividers.classList.add("hide");
      for (var i = 0; i < thermal_bridges_id.length; i++) {
        group = document.getElementById(thermal_bridges_id[i]).parentElement
        group.classList.add("hide");
      }
      thermal_bridges.classList.add("hide");
      break;

    case "constructions":
      constructions.classList.remove("hide");
      constructions.getElementsByClassName("edit")[0].classList.remove("hide");
      left.appendChild(constructions);

      materials.classList.remove("hide");
      materials.getElementsByClassName("edit")[0].classList.add("hide");
      right.appendChild(materials);

      for (var i =  0; i < groups_id.length; i++) {
        group = document.getElementById(groups_id[i]).parentElement
        group.classList.remove("hide");
        right.insertBefore(group, materials)
      }

      air_gaps.classList.remove("hide");
      right.insertBefore(air_gaps, materials)

      construction_sets.classList.add("hide");
      glazings.classList.add("hide");
      frame_and_dividers.classList.add("hide");
      for (var i = 0; i < thermal_bridges_id.length; i++) {
        group = document.getElementById(thermal_bridges_id[i]).parentElement
        group.classList.add("hide");
      }
      thermal_bridges.classList.add("hide");
      break;

    case "materials":
      materials.classList.remove("hide");
      materials.getElementsByClassName("edit")[0].classList.remove("hide");
      left.appendChild(materials);

      for (var i = 0; i < groups_id.length; i++) {
        group = document.getElementById(groups_id[i]).parentElement
        group.classList.remove("hide");
        left.insertBefore(group, materials)
      }

      construction_sets.classList.add("hide");
      constructions.classList.add("hide");
      air_gaps.classList.add("hide");
      glazings.classList.add("hide");
      frame_and_dividers.classList.add("hide");
      for (var i = 0; i < thermal_bridges_id.length; i++) {
        group = document.getElementById(thermal_bridges_id[i]).parentElement
        group.classList.add("hide");
      }
      thermal_bridges.classList.add("hide");

      for (var i = 0; i < spans.length; i++) {
        spans[i].classList.add('hide');
      }
      break;

    case "windows":
      glazings.classList.remove("hide");
      glazings.getElementsByClassName("edit")[0].classList.remove("hide");
      left.appendChild(glazings);

      frame_and_dividers.classList.remove("hide");
      left.appendChild(frame_and_dividers);

      construction_sets.classList.add("hide");
      constructions.classList.add("hide");
      for (var i = 0; i < groups_id.length; i++) {
        group = document.getElementById(groups_id[i]).parentElement
        group.classList.add("hide");
      }
      air_gaps.classList.add("hide");
      materials.classList.add("hide");
      for (var i = 0; i < thermal_bridges_id.length; i++) {
        group = document.getElementById(thermal_bridges_id[i]).parentElement
        group.classList.add("hide");
      }
      thermal_bridges.classList.add("hide");
      break;

    case "thermal_bridges":
      thermal_bridges.classList.remove("hide");
      thermal_bridges.getElementsByClassName("edit")[0].classList.remove("hide");
      left.appendChild(thermal_bridges);

      for (var i = 0; i < thermal_bridges_id.length; i++) {
        group = document.getElementById(thermal_bridges_id[i]).parentElement
        group.classList.remove("hide");
        left.insertBefore(group, thermal_bridges);
      }

      construction_sets.classList.add("hide");
      constructions.classList.add("hide");
      for (var i = 0; i < groups_id.length; i++) {
        group = document.getElementById(groups_id[i]).parentElement
        group.classList.add("hide");
      }
      air_gaps.classList.add("hide");
      materials.classList.add("hide");
      glazings.classList.add("hide");
      frame_and_dividers.classList.add("hide");
      break;
  }
}

window.onload = function() {
  sketchup.add_construction_set_layout();
  sketchup.add_lists();
  select_tab(document.getElementById("input").getElementsByTagName("button")[0]);
  sketchup.add_standards_information();
  sketchup.set_render("input", null, null);
};

function set_render(render) {
  var aux = document.querySelectorAll('#left .selected');
  if (aux.length > 0) {
    sketchup.set_render(render.options[render.selectedIndex].value, aux[0].parentElement.parentElement.id, aux[0].innerHTML)
  } else {
    sketchup.set_render(render.options[render.selectedIndex].value, null, null)
  }
}

$("#input button").click(function() {
  select_tab(this);
});

function add_internal_source_row(tbody, source_layer) {
  var row = tbody.insertRow(source_layer);
  row.setAttribute("id", "internal_source");
  var empty = row.insertCell(0);
  empty.innerHTML = "";
  var internal_source = row.insertCell(1);
  internal_source.innerHTML = "INTERNAL SOURCE";
  internal_source.colSpan = "4";
  internal_source.style.textAlign = "center";
  internal_source.style.fontWeight = "bold";
}

$("#internal_source_check").click(function() {
  sketchup.toggle_layered_construction(document.querySelectorAll("#left .selected")[0].innerHTML);
});

$("#edge_insulation_check").click(function() {
  if (this.checked) {
    document.getElementsByClassName('glyphicon-sort')[0].classList.add('hide')
    document.getElementById("interior_horizontal_insulation").classList.remove("hide");
    document.getElementById("exterior_vertical_insulation").classList.remove("hide");
  } else {
    document.getElementsByClassName('glyphicon-sort')[0].classList.remove('hide')
    document.getElementById("interior_horizontal_insulation").classList.add("hide");
    document.getElementById("exterior_vertical_insulation").classList.add("hide");
  }
  sketchup.toggle_edge_insulation(document.querySelectorAll("#left .selected")[0].innerHTML);
});

function toggle_list(list_id, toggle) {
  var li = document.getElementById(list_id);

  if (!toggle && li.classList.contains("open")) {
    return;
  }
  li.classList.toggle("open");
}

$("body").on("click", "div > ul > li:not(.edit)", function(event) {
  if (this === event.target) {
    toggle_list(this.id, true);
  }
});

function select_li(li) {
  li.classList.add("selected");

  var aux = li.parentElement.parentElement;

  var edits = document.querySelectorAll("#left .edit")
  for (var i = 0; i < edits.length; i++) {
    var spans = edits[i].parentElement.getElementsByTagName("SPAN");
    for (var j = 1; j < spans.length; j++) {
      if (aux.nextElementSibling === edits[i]) {
        spans[j].classList.remove("hide");
      } else {
        spans[j].classList.add("hide");
      }
    }
  }

  var tabs = document.getElementById("output").getElementsByClassName("btn btn-success");
  if (tabs.length === 0) {
    var id = aux.getAttribute("id");
    if (document.getElementById("input").getElementsByClassName("btn btn-success")[0].value === "materials" && aux.parentElement.classList.contains("cte")) {
      document.getElementById("material").classList.remove("hide");
    } else if (!aux.parentElement.classList.contains("cte")) {
      document.getElementById(id.slice(0, -1)).classList.remove("hide");
    }
    sketchup.show_li(id, li.innerHTML);
  }
}

$("#left").click(function() {
  unselect_left();
});

function add_li(id, object_name) {
  var sub_list = document.querySelectorAll("#"+id+" > ul")[0];
  var li = document.createElement("li");
  li.appendChild(document.createTextNode(object_name));
  sub_list.appendChild(li);
  select_li(li);
  toggle_list(id, false);
}

$(".glyphicon-plus").click(function() {
  var aux = this.parentElement.previousElementSibling;
  sketchup.add_object(aux.getAttribute('id'));
});

$(".glyphicon-duplicate").click(function() {
  var aux = this.parentElement.previousElementSibling;
  sketchup.duplicate_object(aux.getAttribute('id'), aux.getElementsByClassName('selected')[0].innerHTML);
});

$(".glyphicon-sort").click(function() {
  var aux = this.parentElement.previousElementSibling;
  sketchup.reverse_construction(aux.getElementsByClassName('selected')[0].innerHTML);
});

function remove_li(id, inner_html) {
  var ul = document.getElementById(id).children[0];
  var lis = ul.children;
  for (var i = 0; i < lis.length; i++) {
   if (lis[i].innerHTML === inner_html) {
      ul.removeChild(lis[i]);
      break;
    }
  }
}

$(".glyphicon-trash").click(function() {
  var aux = this.parentElement.previousElementSibling;
  var selected_li = aux.getElementsByClassName('selected')[0];
  sketchup.remove_object(aux.getAttribute('id'), selected_li.innerHTML);
  aux.getElementsByTagName('UL')[0].removeChild(selected_li);
});

var left_timer;
$("body").on("click", "#left > ul > li > ul > li", function(){
  var li = this;
  if (left_timer) clearTimeout(left_timer);
  left_timer = setTimeout(function(){
    select_li(li);
  },100);
});
$("body").on("dblclick", "#left > ul > li > ul > li", function(){
  clearTimeout(left_timer);
  if (!this.parentElement.parentElement.parentElement.classList.contains("cte")) {
    var old_name = this.innerHTML;
    var input = document.createElement("input");
    input.setAttribute("id", "old_name");
    input.value = old_name;
    input.onblur = function() {
      var new_name = this.value;
      sketchup.rename_object(this.parentElement.parentElement.parentElement.getAttribute("id"), old_name, new_name);
    }
    this.innerHTML = "";
    this.appendChild(input);
    input.focus();
  }
});

var right_timer;
$("body").on("click", "#right > ul > li > ul > li", function(){
  var li = this;
  if (right_timer) clearTimeout(right_timer);
  right_timer = setTimeout(function(){
  },100);
});
$("body").on("dblclick", "#right > ul > li > ul > li", function(){
  clearTimeout(right_timer);
  var left_li = document.querySelectorAll("#left .selected");
  if (left_li.length > 0) {
    var tab = document.getElementById("input").getElementsByClassName("btn btn-success")[0]
    var div_selected = document.querySelectorAll("#" + tab.value.slice(0, -1) + " div > div.selected");
    switch (tab.value) {
      case "construction_sets":
        if (div_selected.length > 0) {
          sketchup.add_default_construction(div_selected[0].getAttribute("id"), left_li[0].innerHTML, this.innerHTML);
        }
        break;

      case "constructions":
        var selected_rows = document.querySelectorAll("tbody tr.selected");
        if (selected_rows.length > 0) {
          sketchup.replace_layer(left_li[0].innerHTML, this.innerHTML, selected_rows[0].cells[0].innerHTML);
        } else {
          if (div_selected.length > 0) {
            if (div_selected[0].getElementsByTagName('p')[1].innerHTML === "") {
              sketchup.add_edge_insulation(div_selected[0].getAttribute("id"), left_li[0].innerHTML, this.innerHTML);
            } else {
              var thickness = div_selected[0].previousElementSibling.previousElementSibling.getElementsByTagName("input")[0].value;
              sketchup.replace_edge_insulation(div_selected[0].getAttribute("id"), left_li[0].innerHTML, this.innerHTML, parseFloat(thickness));
            }
          } else {
            sketchup.add_layer(left_li[0].innerHTML, this.innerHTML);
          }
        }
        break;

      case "materials":
        break;
    }
  }
});

$("#construction_set, #construction").click(function(){
  var selected_divs = document.querySelectorAll("#"+this.id+" div > div.selected");
  if (selected_divs.length > 0) {
    selected_divs[0].classList.remove("selected");
  }
  var selected_rows = document.querySelectorAll("#layers tbody tr.selected");
  if (selected_rows.length > 0) {
    selected_rows[0].classList.remove("selected");
  }
});

var div_timer;
$("#construction_set, #bottom").on("click", "div:not(#reverse_construction) > div", function(){
  var aux = this;
  if (div_timer) clearTimeout(div_timer);
  div_timer = setTimeout(function(){
    aux.classList.add("selected");
  },100);
});
$("#construction_set, #bottom").on("dblclick", "div:not(#reverse_construction) > div", function(){
  clearTimeout(div_timer);
  var tab = document.getElementById("input").getElementsByClassName("btn btn-success")[0]
  var left_li = document.querySelectorAll("#left .selected");
  switch (tab.value) {
    case "construction_sets":
      sketchup.remove_default_construction(this.id, left_li[0].innerHTML);
      break;
    case "constructions":
      sketchup.remove_edge_insulation(this.id, left_li[0].innerHTML);
      break;
    case "materials":
      break;
  }
});

$("#layers").on("blur", "td", function() {
  sketchup.edit_layer(document.querySelectorAll("#left .selected")[0].innerHTML, parseFloat(this.innerHTML)/100, this.parentElement.cells[0].innerHTML);
});

var row_timer;
$("#layers tbody.editable").on("click", "tr", function(){
  var aux = this;
  if (row_timer) clearTimeout(row_timer);
  row_timer = setTimeout(function(){
    if (aux.getAttribute("id") === null) {
      aux.classList.add("selected");
    }
  },100);
})
$("#layers tbody.editable").on("dblclick", "tr", function(){
  clearTimeout(row_timer);

  if (this.getAttribute("id")) {
    this.remove();
    document.getElementById("internal_source_check").checked = false;
    sketchup.toggle_layered_construction(document.querySelectorAll("#left .selected")[0].innerHTML);
  } else {
    var rows = document.querySelectorAll("#layers tbody.editable tr");
    if ((!document.getElementById('edge_insulation_check').checked || rows.length > 2) && (!document.getElementById('internal_source_check').checked || rows.length > 3)) {
      sketchup.remove_layer(document.querySelectorAll("#left .selected")[0].innerHTML, this.cells[0].innerHTML);
    }
  }
});

function setEndOfContenteditable(contentEditableElement) {
  var range, selection;
  if (document.createRange) //Firefox, Chrome, Opera, Safari, IE 9+
  {
    range = document.createRange(); //Create a range (a range is a like the selection but invisible)
    range.selectNodeContents(contentEditableElement); //Select the entire contents of the element with the range
    range.collapse(false); //collapse the range to the end point. false means collapse to end rather than the start
    selection = window.getSelection(); //get the selection object (allows you to change selection)
    selection.removeAllRanges(); //remove any selections already made
    selection.addRange(range); //make the range you have just created the visible selection
  } else if (document.selection) { //IE 8 and lower
    range = document.body.createTextRange(); //Create a range (a range is a like the selection but invisible)
    range.moveToElementText(contentEditableElement); //Select the entire contents of the element with the range
    range.collapse(false); //collapse the range to the end point. false means collapse to end rather than the start
    range.select(); //Select the range (make it the visible selection
  }
}

$("#layers tbody.editable").sortable({
  cancel: "[contenteditable]",
  start: function(event, ui) {
    return ui.placeholder.children().each(function(index, child) {
      var source;
      source = ui.helper.children().eq(index);
      $(child).removeAttr('class').removeAttr('colspan');
      $(child).addClass(source.attr('class'));
      if (source.attr('colspan')) {
        return $(child).attr('colspan', source.attr('colspan'));
      }
    });
  },
  update: function(event, ui){
    var indices = [];
    var source_layer = -1;
    var rows = this.rows;
    var j = 1;
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      if (rows[i].getAttribute("id")) {
        source_layer = j-1;
      } else {
        var index = row.cells[0]
        indices.push(index.innerHTML);
        index.innerHTML = j;
        j += 1;
      }
    }
    if (source_layer > -1) {
      rows[source_layer].remove();
      source_layer = Math.max(source_layer, 1);
      source_layer = Math.min(source_layer, rows.length-1);
      add_internal_source_row(document.querySelectorAll('tbody.editable')[0], source_layer);
    }
    sketchup.sort_layers(document.querySelectorAll("#left .selected")[0].innerHTML, indices, source_layer);
  }
}).disableSelection();

$("#layers tbody.editable").on("mousedown", "[contenteditable]", function(event) {
  this.focus();
  setEndOfContenteditable(event.target);
});

$("#interior_horizontal_insulation input, #exterior_vertical_insulation input").change(function() {
  sketchup.edit_edge_insulation(this.id, document.querySelectorAll('#left .selected')[0].innerHTML, parseFloat(this.value));
});

$("#material input").change(function() {
  sketchup.edit_material(this.id, document.querySelectorAll('#left .selected')[0].innerHTML, parseFloat(this.value));
});

$("#glazing input").change(function() {
  sketchup.edit_glazing(this.id, document.querySelectorAll('#left .selected')[0].innerHTML, parseFloat(this.value));
});

$("#glazing select").change(function() {
  sketchup.edit_standards_information(this.id, document.querySelectorAll('#left .selected')[0].innerHTML, this.options[this.selectedIndex].text);
});

$("#frame input, #frame select").change(function() {
  sketchup.edit_frame(this.id, document.querySelectorAll('#left .selected')[0].innerHTML, parseFloat(this.value));
});

$("#thermal_bridge input").change(function() {
  sketchup.edit_thermal_bridge(this.id, document.querySelectorAll('#left .selected')[0].innerHTML, parseFloat(this.value));
});

$("#thermal_bridge select").change(function() {
  sketchup.edit_thermal_bridge(this.id, document.querySelectorAll('#left .selected')[0].innerHTML, this.value);
});

$("#output button").click(function() {
  var tabs = document.querySelectorAll("#output > button");
  for (var i = 0; i < tabs.length; i++) {
    tabs[i].className = tabs[i].className.replace("btn btn-success", "btn btn-secondary");
  }
  this.className = this.className.replace("btn btn-secondary", "btn btn-success");

  hide_main_divs();
  document.getElementById("results").classList.remove("hide");
  document.getElementById("right").classList.add("hide");

  sketchup.compute_k_global(this.value);
});

function unselect_rows() {
  var rows = document.querySelectorAll("#results tbody tr");
  for (var i = 0; i < rows.length; i++) {
    rows[i].classList.remove("selected");
  }
}

$("#results").click(function() {
  unselect_rows();
}).on("click", "tbody tr", function(event) {
  unselect_rows();

  this.classList.add("selected");
  sketchup.select_object(document.getElementById("output").getElementsByClassName("btn btn-success")[0].value, this.cells[0].innerHTML);

  event.stopPropagation();
});
