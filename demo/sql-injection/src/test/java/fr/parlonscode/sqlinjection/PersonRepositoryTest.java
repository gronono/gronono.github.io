package fr.parlonscode.sqlinjection;

import java.util.List;

import org.junit.Assert;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.junit4.SpringRunner;

@RunWith(SpringRunner.class)
@SpringBootTest
public class PersonRepositoryTest {

	@Autowired
	private PersonRepository repo;
	
	@Test
	public void testFindByName() {
		// Non injection
		List<Person> result = repo.findByName("dsyer");
		Assert.assertEquals(1, result.size());
		Assert.assertEquals("dsyer", result.get(0).getName());
		
		// Test injection
		result = repo.findByName("dsyer' or '1'='1");
		Assert.assertEquals(0, result.size());		
	}

	@Test
	public void testQueryByName() {
		// Non injection
		List<Person> result = repo.queryByName("dsyer");
		Assert.assertEquals(1, result.size());
		Assert.assertEquals("dsyer", result.get(0).getName());
		
		// Test injection
		result = repo.queryByName("dsyer' or '1'='1");
		Assert.assertEquals(0, result.size());		
	}
}
