// Decompile functions containing explicitly supplied virtual addresses.
// @category Warblade

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class DecompileAddresses extends GhidraScript {
	@Override
	public void run() throws Exception {
		DecompInterface decompiler = new DecompInterface();
		decompiler.openProgram(currentProgram);
		for (String argument : getScriptArgs()) {
			Address address = toAddr(argument);
			Function function = getFunctionContaining(address);
			if (function == null) {
				function = getFunctionAt(address);
			}
			if (function == null) {
				println("NO_FUNCTION " + argument);
				continue;
			}
			DecompileResults result = decompiler.decompileFunction(function, 120, monitor);
			println(
				"=== " + argument + " " + function.getName() + " " +
				function.getEntryPoint() + " ==="
			);
			if (!result.decompileCompleted()) {
				println("DECOMPILE_FAILED " + result.getErrorMessage());
				continue;
			}
			println(result.getDecompiledFunction().getC());
		}
		decompiler.dispose();
	}
}
