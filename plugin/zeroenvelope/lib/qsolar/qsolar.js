
window.onload = function() {
  sketchup.load();
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

$("#input button, #output button").click(function() {
  var tabs = document.querySelectorAll("#input button, #output button");
  for (var i = 0; i < tabs.length; i++) {
    tabs[i].className = tabs[i].className.replace("btn btn-success", "btn btn-secondary");
  }
  this.className = this.className.replace("btn btn-secondary", "btn btn-success");
  
  var divs = document.querySelectorAll("#main > div");
  for (var i = 0; i < divs.length; i++) {
    divs[i].classList.add("hide");
  }

  switch (this.value) {
    case "input":
      var lis = document.querySelectorAll("#left > ul > li:not(.edit) > ul > li.selected");
      if (lis.length > 0) {
        select_li(lis[0]);
      }
      break;
      
    case "output":
      document.getElementById("results").classList.remove("hide");
      sketchup.compute_shadows();
      set_render(document.getElementById("render"));
      break;
  }
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
  
  var id = aux.getAttribute("id");
  if (document.querySelectorAll("#input button.btn-success").length > 0) {
    document.getElementById(id.slice(0, -1)).classList.remove("hide");
  }
  sketchup.show_li(id, li.innerHTML);
}

$("#left").click(function() {
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

  var divs = document.querySelectorAll("#main > div");
  for (var i = 0; i < divs.length; i++) {
    divs[i].classList.add("hide");
  }
  if (document.querySelectorAll("#output button.btn-success").length > 0) {
    document.getElementById("results").classList.remove("hide");
  }
  
  sketchup.render_white();
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

$(".glyphicon-duplicate").click(function() {
  var aux = this.parentElement.previousElementSibling;
  sketchup.duplicate_object(aux.getAttribute('id'), aux.getElementsByClassName('selected')[0].innerHTML);
});

$("#main input").change(function() {
  var aux = document.querySelectorAll('#left .selected')[0];
  sketchup.edit_object(aux.parentElement.parentElement.id, aux.innerHTML, this.id, parseFloat(this.value));
});

$("#main select").change(function() {
  var aux = document.querySelectorAll('#left .selected')[0];
  sketchup.edit_object(aux.parentElement.parentElement.id, aux.innerHTML, this.id, this.options[this.selectedIndex].value);
});

$(".glyphicon-trash").click(function() {
  var aux = this.parentElement.previousElementSibling;
  var selected_li = aux.getElementsByClassName('selected')[0];
  sketchup.remove_object(aux.getAttribute('id'), selected_li.innerHTML);
  aux.getElementsByTagName('UL')[0].removeChild(selected_li);
});

$("#render").change(function() {
  set_render(this);
});

function unselect() {
  var rows = document.querySelectorAll("tbody tr");
  for (var i = 0; i < rows.length; i++) {
    rows[i].classList.remove("selected");
  }
}

$("#main").click(function() {
  unselect();
}).on("click", "tbody tr", function(event) {
  unselect();

  this.classList.add("selected");
  sketchup.select_sub_surface(this.cells[0].innerHTML);
  
  event.stopPropagation();
});

$("th").click(function() {
  var i, x, y, temp, shouldSwitch, switchcount = 0;
  var n = $(this).closest("th").index();
  var table = document.getElementsByTagName('tbody')[0];
  var rows = table.rows;
  var switching = true;
  //Set the sorting direction to ascending:
  var dir = "asc"; 
  /*Make a loop that will continue until
  no switching has been done:*/
  while (switching) {
    //start by saying: no switching is done:
    switching = false;
    /*Loop through all table rows (except the
    first, which contains table headers):*/
    for (i = 0; i < (rows.length - 1); i++) {
      //start by saying there should be no switching:
      shouldSwitch = false;
      /*Get the two elements you want to compare,
      one from current row and one from the next:*/
      x = rows[i].getElementsByTagName("TD")[n].innerHTML;
      y = rows[i + 1].getElementsByTagName("TD")[n].innerHTML;
      /*check if the two rows should switch place,
      based on the direction, asc or desc:*/
      if (isNaN(x)) {
        if (x.includes("Sub Surface ")) {
          temp = x.split(" ");
          x = parseInt(temp[temp.length-1]);
          temp = y.split(" ");
          y = parseInt(temp[temp.length-1]);
        } else {
          x = x.toLowerCase();
          y = y.toLowerCase();
        }
      } else {
        x = parseFloat(x);
        y = parseFloat(y);
      }
      if (dir == "asc") {
        if (x > y) {
          //if so, mark as a switch and break the loop:
          shouldSwitch= true;
          break;
        }
      } else if (dir == "desc") {
        if (x < y) {
          //if so, mark as a switch and break the loop:
          shouldSwitch = true;
          break;
        }
      }
    }
    if (shouldSwitch) {
      /*If a switch has been marked, make the switch
      and mark that a switch has been done:*/
      rows[i].parentNode.insertBefore(rows[i + 1], rows[i]);
      switching = true;
      //Each time a switch is done, increase this count by 1:
      switchcount ++;      
    } else {
      /*If no switching has been done AND the direction is "asc",
      set the direction to "desc" and run the while loop again.*/
      if (switchcount == 0 && dir == "asc") {
        dir = "desc";
        switching = true;
      }
    }
  }
  
  var sub_surface_names = [];
  for (i = 0; i < rows.length; i++) {
    sub_surface_names.push(rows[i].getElementsByTagName("TD")[0].innerHTML);
  }
  sketchup.sort_sub_surfaces(sub_surface_names);
});