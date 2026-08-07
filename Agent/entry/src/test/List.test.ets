import localUnitTest from './LocalUnit.test';
import accountUnitTest from './AccountUnit.test';

export default function testsuite() {
  localUnitTest();
  accountUnitTest();
}
