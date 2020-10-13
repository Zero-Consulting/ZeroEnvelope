# ZeroEnvelope

The Zero Envelope SketchUp plugin is an OpenStudio design tool that computes some energy efficiency indicators of the thermal envelope according to the CTE DB-HE.

## Installation

* SketchUp 2019 or newer is needed for **q solar** tool.
* Install [OpenStudio SketchUp Plug-in](https://github.com/openstudiocoalition/openstudio-sketchup-plugin).
* Donwload the [RBZ](https://github.com/agonzalezesteve/ZeroEnvelope/blob/main/ZeroEnvelope.rbz) file and [install it manually](https://help.sketchup.com/en/extension-warehouse/adding-extensions-sketchup#install-manual) in SketchUp.

## K global

* Automatic U values taking into account the different boundary conditions and linear transmittances of thermal bridges.
* The calculations are explained in the [Zero Consulting blog](https://blog.zeroconsulting.com/nuevo-cte-he-2019-kglobal).
* Good complement to the [OpenStudio Application](https://github.com/openstudiocoalition/OpenStudioApplication) for editing Layered Constructions.
* Good complement to [SG Save](http://www.efinovatic.es/energyPlus/) for introducing thermal bridges.

## q solar

* Automatic solar heat gains trough windows in July with active solar protection.
* The [polygon clipping](https://bigladdersoftware.com/epx/docs/9-4/engineering-reference/shading-module.html#polygon-clipping) algorithm is implemented for computing the [shading factors](https://bigladdersoftware.com/epx/docs/9-4/engineering-reference/sky-radiance-model.html#shadowing-of-sky-diffuse-solar-radiation) in order to avoid the run time of the EnergyPlus simulation.
* The [geom2d](https://github.com/gettalong/geom2d) library is used for polygon clipping but using the [rbclipper](https://github.com/mieko/rbclipper) algorithm.

## License

[MIT](https://choosealicense.com/licenses/mit/)