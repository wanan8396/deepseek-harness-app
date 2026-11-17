package app.dsh.files

import app.dsh.runtime.PhoneStorage
import org.junit.Assert.*
import org.junit.Test

class FilesOutputsTest {

    @Test fun outputDirectoryIsTheCurrentShellFriendlyProductName() {
        // Independent contract: do not derive this expectation from the production constant.
        assertEquals("DeepSeek-harness", PhoneStorage.OUTPUT_SUBDIR)
    }

}
