"""Polygon conversion checks; no claim about AVM1 collision implementation."""
import unittest
import geometry


class GeometryTests(unittest.TestCase):
    def check_conversion(self,paths,bounds):
        output=geometry.filled_trapezoids(paths,bounds)
        for xi in range(1,70):
            for yi in range(1,70):
                p=[bounds[0]+(bounds[2]-bounds[0])*(xi+0.127)/71,
                   bounds[1]+(bounds[3]-bounds[1])*(yi+0.419)/71]
                expected=sum(geometry.point_inside(p,path) for path in paths)%2
                actual=sum(geometry.point_inside(p,path) for path in output)
                self.assertEqual(actual,expected,(p,output))
        return output
    def test_hole_remains_walkable(self):
        self.check_conversion([[[0,0],[100,0],[100,100],[0,100]],[[20,20],[20,80],[80,80],[80,20]]],[10,10,90,90])
    def test_diagonal_clipping(self):
        self.check_conversion([[[-20,5],[90,80],[10,90]]],[0,0,70,100])
    def test_nested_holes(self):
        self.check_conversion([[[0,0],[100,0],[100,100],[0,100]],[[10,10],[90,10],[90,90],[10,90]],
            [[40,40],[60,40],[60,60],[40,60]]],[0,0,100,100])
    def test_original_spawn_kept(self):
        self.assertEqual(geometry.safe_spawn([50,50],[0,0,100,100],[]),([50,50],False))
    def test_outside_spawn_is_explicitly_adjusted(self):
        point,changed=geometry.safe_spawn([-10,50],[0,0,100,100],[])
        self.assertTrue(changed);self.assertEqual(point,[20,50])
    def test_blocked_right_wall_exit_uses_free_corridor(self):
        row=geometry.manual_exit([0,0,200,100],[[[170,0],[200,0],[200,100],[170,100]]])
        self.assertLessEqual(row['rect'][2],170)


if __name__=='__main__':unittest.main()
