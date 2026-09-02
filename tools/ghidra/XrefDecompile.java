// For each supplied data virtual address: list code references to it and
// decompile every referencing function (deduplicated).
// @category Warblade

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;

import java.util.LinkedHashSet;
import java.util.Set;

public class XrefDecompile extends GhidraScript {
	@Override
	public void run() throws Exception {
		DecompInterface decompiler = new DecompInterface();
		decompiler.openProgram(currentProgram);
		Set<Function> functions = new LinkedHashSet<>();
		for (String argument : getScriptArgs()) {
			Address address = toAddr(argument);
			println("### XREFS " + argument);
			ReferenceIterator references =
				currentProgram.getReferenceManager().getReferencesTo(address);
			int count = 0;
			while (references.hasNext()) {
				Reference reference = references.next();
				Address from = reference.getFromAddress();
				Function function = getFunctionContaining(from);
				println(
					"REF " + argument + " <- " + from + " " +
					reference.getReferenceType() + " " +
					(function == null ? "(no function)" : function.getName() + " @ " + function.getEntryPoint())
				);
				if (function != null) {
					functions.add(function);
				}
				count += 1;
			}
			if (count == 0) {
				println("NO_XREFS " + argument);
			}
		}
		for (Function function : functions) {
			println("=== FUNCTION " + function.getName() + " " + function.getEntryPoint() + " ===");
			DecompileResults result = decompiler.decompileFunction(function, 180, monitor);
			if (!result.decompileCompleted()) {
				println("DECOMPILE_FAILED " + result.getErrorMessage());
				continue;
			}
			println(result.getDecompiledFunction().getC());
		}
		decompiler.dispose();
	}
}
