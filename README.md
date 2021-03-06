# ZeroEnvelope

The ZeroEnvelope SketchUp plugin is an OpenStudio design tool that computes some energy efficiency indicators of the thermal envelope according to the CTE DB-HE (Spanish Technical Building Code).

Based on the idea from [EnvolventeCTE](https://pachi.github.io/envolventecte) of getting quick indicators of the building envelope, this plugin simplifies the introduction of data into an OpenStudio model and plots the results in SketchUp.

### K global

[![Zero Envelope - K global - 201015 Demo](http://img.youtube.com/vi/NnLzam9g170/0.jpg)](http://www.youtube.com/watch?v=NnLzam9g170 "K global demo")

* Automatic U values taking into account the different boundary conditions and linear transmittances of thermal bridges (calculations are explained in the [Zero Consulting blog](https://blog.zeroconsulting.com/nuevo-cte-he-2019-kglobal)).
* Good complement to the [OpenStudio Application](https://github.com/openstudiocoalition/OpenStudioApplication) for editing Layered Constructions and assigning Constructions.
* Good complement to [SG Save](http://www.efinovatic.es/energyPlus/) for introducing thermal bridges.

### q solar

[![Zero Envelope - q solar - 201015 Demo](http://img.youtube.com/vi/iTK3uvhkkqs/0.jpg)](http://www.youtube.com/watch?v=iTK3uvhkkqs "q solar demo")

* Automatic solar heat gains through windows in July with active solar protection and window setback.
* The [polygon clipping](https://bigladdersoftware.com/epx/docs/9-4/engineering-reference/shading-module.html#polygon-clipping) algorithm is implemented for computing the [shading factors](https://bigladdersoftware.com/epx/docs/9-4/engineering-reference/sky-radiance-model.html#shadowing-of-sky-diffuse-solar-radiation) in order to avoid the simulation time of the EnergyPlus simulation.
* The [geom2d](https://github.com/gettalong/geom2d) library is used for polygon clipping but using the [rbclipper](https://github.com/mieko/rbclipper) algorithm.


## Installation

* SketchUp 2019 or newer is required for **q solar** tool.
* Install the [OpenStudio SketchUp Plug-in](https://github.com/openstudiocoalition/openstudio-sketchup-plugin).
* Donwload the [RBZ](https://github.com/agonzalezesteve/ZeroEnvelope/releases/latest/download/zeroenvelope.rbz) file and [install it manually](https://help.sketchup.com/en/extension-warehouse/adding-extensions-sketchup#install-manual) in SketchUp.

## Usage

* Rename objects, from the lists on the left, double clicking its name.
* Assign objects selecting entities in SketchUp and using the buttons at the bottom left.
* If you render by input: the entities with the selected object are painted in green, white entities have other objects assigned and the grey ones have no object assigned.

### K global

* Define uninhabitable spaces using the "Part of Total Floor Area" flag.
* In Construction Sets:
  * add an object to the construction set selecting the planar surface type and double clicking the construction from the list on the right and
  * remove a construction from the construction set double clicking its name.
* In Constructions:
  * add a layer to a construction double clicking a material from the list on the right,
  * sort layers dragging table rows,
  * edit the thickness of a layer clicking on it (if the material is editable) and
  * remove a layer double clicking its row.
* In Constructions you can:
  * add an internal source,
  * add edge insulation and
  * reverse asymmetric constructions to mirror adjacent surfaces (check it rendering by mirror).

### q solar

* Sort the results table by clicking on the header names.

## License

[MIT](https://choosealicense.com/licenses/mit/)